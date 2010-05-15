module ListWidget (
  ListWidget
, newListWidget
, moveUp
, moveDown
, scrollUp
, scrollDown
, scrollPageUp
, scrollPageDown
, select
, renderListWidget
) where

import UI.Curses hiding (wgetch, ungetch, mvaddstr)

data ListWidget a = ListWidget {
  position    :: Int
, offset      :: Int
, getList     :: [a]
, renderOne   :: a -> String
, getView     :: Window       -- ^ the window, this widget is rendered to
, getViewSize :: Int          -- ^ number of lines that can be displayed at once
}

newListWidget :: (a -> String) -> [a] -> Window -> IO (ListWidget a)
newListWidget aToString aList window = do
  (sizeY, _) <- getmaxyx window
  return ListWidget { position    = 0
                    , offset      = 0
                    , getList     = aList
                    , renderOne   = aToString
                    , getViewSize = sizeY
                    , getView     = window
                    }

moveUp :: ListWidget a -> ListWidget a
moveUp l = l {position = newPosition, offset = min currentOffset newPosition}
  where
    currentOffset = offset l
    newPosition   = max 0 (position l - 1)

moveDown :: ListWidget a -> ListWidget a
moveDown l = l {position = newPosition, offset = max currentOffset minOffset}
  where
    currentPosition = position l
    currentOffset   = offset l
    newPosition     = min (length (getList l) - 1) (currentPosition + 1)
    minOffset       = newPosition - (getViewSize l - 1)


scrollUp_ :: Int -> ListWidget a -> ListWidget a
scrollUp_ n l = l {offset = newOffset, position = min currentPosition maxPosition}
  where
    currentPosition = position l
    maxPosition     = getViewSize l - 1 + newOffset
    newOffset       = max 0 $ offset l - n

scrollDown_ :: Int -> ListWidget a -> ListWidget a
scrollDown_ n l = l {offset = newOffset, position = max currentPosition newOffset}
  where
    listLength      = length $ getList l
    currentPosition = position l
    newOffset       = min (listLength - 1) $ offset l + n

-- | offset for page scroll
pageScroll :: ListWidget a -> Int
pageScroll l = max 0 $ getViewSize l - 2

scrollUp, scrollPageUp :: ListWidget a -> ListWidget a
scrollUp       = scrollUp_ 1
scrollPageUp l = scrollUp_ (pageScroll l) l

scrollDown, scrollPageDown :: ListWidget a -> ListWidget a
scrollDown       = scrollDown_ 1
scrollPageDown l = scrollDown_ (pageScroll l) l


select :: ListWidget a -> a
select l = getList l !! position l

renderListWidget :: ListWidget a -> IO ()
renderListWidget l = do
  let win = getView l
  (sizeY, sizeX) <- getmaxyx win

  let currentPosition = position l
  let currentOffset = offset l
  let list = take sizeY $ drop currentOffset $ getList l

  werase win

  let aString = ("  " ++) . renderOne l
  let putLine (y, e) = mvwaddnstr win y 0 (aString e) sizeX
  mapM_ putLine $ zip [0..] list

  let relativePosition = currentPosition - currentOffset
  mvwaddstr win relativePosition 0 $ "*"

  wrefresh win
  return ()
