{-# LANGUAGE FlexibleContexts, FlexibleInstances, RankNTypes #-}
module Vimus
( Vimus
, ProgramState (..)
, CurrentView (..)
, ContentListWidget
, getCurrentView
, setCurrentView
, modifyCurrentSongList
, withCurrentSongList
, withCurrentSong
, withCurrentItem
, renderMainWindow
, renderToMainWindow
)
where

import Control.Monad.State (get, put, modify, liftM, lift, StateT, MonadState)

import Network.MPD.Core
import qualified Network.MPD as MPD hiding (withMPD)

import UI.Curses (Window)

import Widget (Widget, ContentListWidget)
import qualified Widget

import TextWidget (TextWidget)

import qualified ListWidget

data CurrentView = Playlist | Library | Help | SearchResult | Browser

data ProgramState = ProgramState {
  currentView       :: CurrentView
, playlistWidget    :: ContentListWidget
, libraryWidget     :: ContentListWidget
, searchResult      :: ContentListWidget
, browserWidget     :: ContentListWidget
, helpWidget        :: TextWidget
, mainWindow        :: Window
, statusLine        :: Window
, getLastSearchTerm :: String
}


instance MonadMPD (StateT ProgramState MPD) where
  getVersion  = lift getVersion
  open        = lift open
  close       = lift close
  send        = lift . send
  getHandle   = lift getHandle
  setPassword = lift . setPassword
  getPassword = lift getPassword

type Vimus a = StateT ProgramState MPD a

{-
newtype Vimus a = Vimus {
  runVimus :: StateT ProgramState MPD a
} deriving (Monad, Functor, MonadIO, MonadState ProgramState, MonadError MPDError, MonadMPD)
-}


setCurrentView :: CurrentView -> Vimus ()
setCurrentView v = modify (\state -> state { currentView = v })

getCurrentView :: Vimus CurrentView
getCurrentView = currentView `liftM` get

-- | Modify currently selected song list by applying given function.
modifyCurrentSongList :: (MonadState ProgramState m) => (ContentListWidget -> ContentListWidget) -> m ()
modifyCurrentSongList f = do
  state <- get
  case currentView state of
    Playlist -> put state { playlistWidget = f $ playlistWidget state }
    Library  -> put state { libraryWidget  = f $ libraryWidget  state }
    SearchResult -> put state { searchResult = f $ searchResult state }
    Browser  -> put state { browserWidget  = f $ browserWidget  state }
    Help     -> return ()


-- | Run given action with currently selected song list
withCurrentSongList :: (ContentListWidget -> Vimus ()) -> Vimus ()
withCurrentSongList action =  do
  state <- get
  case currentView state of
    Playlist -> action $ playlistWidget state
    Library  -> action $ libraryWidget  state
    SearchResult -> action $ searchResult state
    Browser  -> action $ browserWidget  state
    Help     -> return ()


-- | Run given action with currently selected item, if any
withCurrentItem :: (MPD.LsResult -> Vimus ()) -> Vimus ()
withCurrentItem action = withCurrentSongList $ \widget ->
  case ListWidget.select widget of
    Just item -> action item
    Nothing   -> return ()

-- | Run given action with currently selected song, if any
withCurrentSong :: (MPD.Song -> Vimus ()) -> Vimus ()
withCurrentSong action = withCurrentItem $ \item ->
  case item of
    MPD.LsFile song -> action song
    _               -> return ()

withCurrentWidget :: (forall a. Widget a => a -> Vimus ()) -> Vimus ()
withCurrentWidget action = do
  state <- get
  case currentView state of
    Playlist -> action $ playlistWidget state
    Library  -> action $ libraryWidget  state
    SearchResult -> action $ searchResult state
    Browser  -> action $ browserWidget  state
    Help     -> case state of ProgramState { helpWidget = x} -> action x


-- | Render currently selected widget to main window
renderMainWindow :: Vimus ()
renderMainWindow = withCurrentWidget renderToMainWindow


-- | Render given widget to main window
renderToMainWindow :: forall a. Widget a => a -> Vimus ()
renderToMainWindow l = do
  s <- get
  Widget.render (mainWindow s) l
