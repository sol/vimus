module Main (main) where

import UI.Curses hiding (wgetch, ungetch, mvaddstr)
import Control.Exception (finally)

import qualified Network.MPD as MPD hiding (withMPD)
import qualified Network.MPD.Commands.Extensions as MPDE
import Network.MPD (Seconds, Port)

import Control.Monad.State

import Data.Either (rights)
import Data.List
import Data.Maybe
import Data.IORef

import Control.Concurrent

import Text.Printf (printf)

import Prelude hiding (getChar)

import qualified WindowLayout
import qualified Input
import Macro (expandMacro)

import qualified ListWidget

import qualified PlaybackState
import           PlaybackState (PlaybackState)

import Option (getOptions)
import Util (withMPDEx_)

import Control.Monad.Loops (whileM_)

import Vimus
import Command (runCommand, search, searchPredicate, filterPredicate, helpScreen)

import qualified Song

------------------------------------------------------------------------
-- playlist widget

createSongListWidget :: (MonadIO m) => Window -> [MPD.Song] -> m SongListWidget
createSongListWidget window songs = liftIO $ do
  (viewSize, _) <- getmaxyx window
  return $ ListWidget.new songs viewSize


updatePlaylist :: Vimus ()
updatePlaylist = do
  state <- get
  songs <- MPDE.getPlaylist
  let newPlaylistWidget = ListWidget.update (playlistWidget state) songs
  put state { playlistWidget = newPlaylistWidget }


updateLibrary :: Vimus ()
updateLibrary = do
  state <- get
  -- it seems that we only get rights here, even with songs that have no
  -- id3tags attached
  songs <- fmap rights $ MPD.listAllInfo ""
  let newWidget = ListWidget.update (libraryWidget state) songs
  put state { libraryWidget = newWidget }


------------------------------------------------------------------------
-- The main event loop

mainLoop :: Window -> Chan Notify -> IO Window -> Vimus ()
mainLoop window chan onResize = do

  -- place cursor on current song, if any
  updatePlaylist
  st <- MPD.status
  case MPD.stSongPos st of
    Just n -> modifyCurrentSongList (\l -> ListWidget.setPosition l n)
    _      -> return ()
  renderMainWindow

  forever $ do
    c <- getChar
    case c of
      ':' ->  do
                input <- Input.readline_ window ':' getChar
                maybe (return ()) runCommand input
      '/' ->  do
                input <- Input.readline searchPreview window '/' getChar
                maybe (return ()) search input
                renderMainWindow
      'F' ->  withCurrentSongList $ \widget -> do
                cache <- liftIO $ newIORef [("", ListWidget.setPosition widget 0)]
                input <- Input.readline (filterPreview cache) window '/' getChar
                case input of
                  Just t  -> do
                    modify $ \state -> state { searchResult = ListWidget.filter (filterPredicate t) widget }
                    setCurrentView SearchResult
                  Nothing -> return ()
                renderMainWindow
      _   ->  do
                expandMacro getChar Input.ungetstr [c]
  where
    searchPreview term =
      withCurrentSongList $ \widget ->
        renderToMainWindow $ ListWidget.search (searchPredicate term) widget

    filterPreview cache term = do
      liftIO $ modifyIORef cache updateCache
      -- cache now contains results for all `inits term', in reverse order
      -- TODO: write some quickcheck properties
      r <- liftIO $ readIORef cache
      renderToMainWindow $ snd $ head r
      where
        updateCache []               = error "this should never happen"
        updateCache list@((t, l):xs) =
          if term == t then
            list
          else if isPrefixOf t term then
            (term, ListWidget.filter (filterPredicate term) l) : list
          else
            updateCache xs

    getChar = do
      handleNotifies chan
      c <- Input.wgetch window
      if c == '\0'
        then getChar
        else if (c == keyResize) then do
          state <- get
          liftIO $ delwin $ mainWindow state
          win <- liftIO onResize
          (sizeY, _) <- liftIO $ getmaxyx win

          let newPlaylistWidget = ListWidget.setViewSize (playlistWidget state) sizeY
          let newLibraryWidget  = ListWidget.setViewSize (libraryWidget state) sizeY

          put state {mainWindow = win, playlistWidget = newPlaylistWidget, libraryWidget = newLibraryWidget}
          renderMainWindow
          getChar
        else return c


data Notify = NotifyPlaylistChanged
            | NotifyLibraryChanged
            | NotifyAction (Vimus ())


handleNotifies :: Chan Notify -> Vimus ()
handleNotifies chan = whileM_ (liftIO $ fmap not $ isEmptyChan chan) $ do
  notify <- liftIO $ readChan chan
  case notify of
    NotifyPlaylistChanged -> updatePlaylist >> renderMainWindow
    NotifyLibraryChanged  -> updateLibrary >> renderMainWindow
    NotifyAction action   -> action


------------------------------------------------------------------------
-- mpd status

updateStatus :: (MonadIO m) => Window -> Window -> PlaybackState -> m ()
updateStatus songWindow playWindow st = do

  putString songWindow song
  putString playWindow playState
  where
    song = fromMaybe "none" $ fmap Song.title $ PlaybackState.currentSong st

    playState = stateSymbol ++ " " ++ formatTime current ++ " / " ++ formatTime total
      where
        (current, total) = PlaybackState.elapsedTime st
        stateSymbol = case PlaybackState.playState st of
          MPD.Playing -> "|>"
          MPD.Paused  -> "||"
          MPD.Stopped -> "[]"

    formatTime :: Seconds -> String
    formatTime s = printf "%02d:%02d" minutes seconds
      where
        minutes = s `div` 60
        seconds = s `mod` 60

    putString :: (MonadIO m) => Window -> String -> m ()
    putString window string = liftIO $ do
      mvwaddstr window 0 0 string
      wclrtoeol window
      wrefresh window
      return ()


------------------------------------------------------------------------
-- Program entry point

run :: Maybe String -> Maybe Port -> IO ()
run host port = do

  (onResize, mw, statusWindow, songStatusWindow, playStatusWindow, inputWindow) <- WindowLayout.create

  -- thread for playback state
  notifyChan <- newChan
  forkIO $ withMPD $ PlaybackState.onChange $ \st -> do
    writeChan notifyChan $ NotifyAction $ updateStatus songStatusWindow playStatusWindow st

  -- thread for asynchronous updates
  liftIO $ writeChan notifyChan NotifyLibraryChanged
  forkIO $ withMPD $ forever $ do
    l <- MPD.idle
    when (MPD.PlaylistS `elem` l) $ do
      liftIO $ writeChan notifyChan NotifyPlaylistChanged
    when (MPD.DatabaseS `elem` l) $ do
      liftIO $ writeChan notifyChan NotifyLibraryChanged


  -- We use a timeout of 10 ms, but be aware that the actual timeout may be
  -- different due to a combination of two facts:
  --
  -- (1) ncurses getch (and related functions) returns when a signal occurs
  -- (2) the threaded GHC runtime uses signals for bookkeeping
  --     (see +RTS -V option)
  --
  -- So the effective timeout swayed by the runtime.
  --
  -- We may workaround this in the future, as suggest here:
  -- http://www.serpentine.com/blog/2010/09/04/dealing-with-fragile-c-libraries-e-g-mysql-from-haskell/
  wtimeout inputWindow 10

  keypad inputWindow True

  mvwaddstr inputWindow 0 0 "type 'q' to exit, read 'src/Macro.hs' for help"
  wrefresh inputWindow

  pl <- createPlaylistWidget mw
  lw <- createLibraryWidget mw
  sr <- createSongListWidget mw []

  withMPD $ runStateT (mainLoop inputWindow notifyChan onResize) ProgramState {
      currentView     = Playlist
    , playlistWidget  = pl
    , libraryWidget   = lw
    , searchResult    = sr
    , helpWidget      = helpScreen
    , mainWindow      = mw
    , statusLine      = statusWindow
    , getLastSearchTerm = ""
    }
  return ()

  where
    createPlaylistWidget :: Window -> IO SongListWidget
    createPlaylistWidget window = createSongListWidget window []

    createLibraryWidget :: Window -> IO SongListWidget
    createLibraryWidget window = createSongListWidget window []

    withMPD :: (MonadIO m) => MPD.MPD a -> m a
    withMPD action = do
      result <- liftIO $ withMPDEx_ host port action
      case result of
          Left  e -> fail $ show e
          Right r -> return r



main :: IO ()
main = do

  (host, port) <- getOptions

  -- recommended in ncurses manpage
  initscr
  raw
  noecho

  -- suggested  in ncurses manpage
  -- nonl
  intrflush stdscr True

  -- enable colors
  start_color
  use_default_colors

  curs_set 0

  finally (run host port) endwin
