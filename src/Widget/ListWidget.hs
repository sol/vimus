{-# LANGUAGE CPP, DeriveFunctor #-}
module Widget.ListWidget (
  ListWidget
, new
, setMarked

-- * current element
, getPosition
, select

-- * movement
, moveUp
, moveDown
, moveLast
, moveFirst

-- * parent and children
, newChild
, getParent

-- * update
, update
, resize

-- * exported, because they have fewer constraints than the Widget variants
, Widget.ListWidget.render
, Widget.ListWidget.searchItem
, Widget.ListWidget.filterItem
, Widget.ListWidget.handleEvent
, Widget.ListWidget.tryMatch

#ifdef TEST

, getListLength
, getViewSize
, getViewPosition
, scroll

#endif
) where

import           Data.List (isInfixOf)
import           Data.Char (toLower)

import           Control.Monad (when)
import           Data.Foldable (forM_)
import           Data.Default

import           Widget.Type
import           WindowLayout
import           Util (clamp)
import           Ruler
import           Render hiding (getWindowSize)
import           Vimus (Widget(..), Event(..), SearchOrder(..))
import           Content

data ListWidget a = ListWidget {
  getPosition     :: Int        -- ^ Cursor position
, getList         :: [a]
, getMarked       :: Maybe Int  -- ^ Marked element
, getListLength   :: Int

, getWindowSize         :: WindowSize

-- | position of viewport within the list
, getViewPosition :: Int

, getParent       :: Maybe (ListWidget a)
} deriving (Eq, Show, Functor)

instance (Searchable a, Renderable a) => Widget (ListWidget a) where
  render      = Widget.ListWidget.render
  currentItem = const Nothing
  searchItem  = Widget.ListWidget.searchItem
  filterItem  = Widget.ListWidget.filterItem
  handleEvent = Widget.ListWidget.handleEvent

handleEvent :: Monad m => ListWidget a -> Event -> m (ListWidget a)
handleEvent l ev = return $ case ev of
  EvMoveUp         -> moveUp l
  EvMoveDown       -> moveDown l
  EvMoveFirst      -> moveFirst l
  EvMoveLast       -> moveLast l
  EvScroll n       -> scroll n l
  EvResize size    -> resize l size
  _                -> l

-- | The number of lines that are available for content.
getViewSize :: ListWidget a -> Int
getViewSize = windowSizeY . getWindowSize

new :: [a] -> ListWidget a
new list = widget
  where
    widget = ListWidget {
        getPosition = 0
      , getList = list
      , getMarked = Nothing
      , getListLength = length list
      , getWindowSize = def
      , getViewPosition = 0
      , getParent = Nothing
      }

newChild :: [a] -> ListWidget a -> ListWidget a
newChild list parent = widget {getParent = Just parent}
  where
    widget = resize (new list) (getWindowSize parent)

resize :: ListWidget a -> WindowSize -> ListWidget a
resize widget size = result {getParent = (`resize` size) `fmap` getParent result}
  where
    w = widget {getWindowSize = size {windowSizeY = max (windowSizeY size) 2}}
    -- to make sure that viewPosition is correct, we simply set position
    result = setPosition w $ getPosition w


update :: ListWidget a -> [a] -> ListWidget a
update widget list = setPosition newWidget $ getPosition widget
  where
    newWidget = widget { getList = list, getListLength = length list, getParent = Nothing }

------------------------------------------------------------------------
-- search


filterItem :: Searchable a => ListWidget a -> String -> ListWidget a
filterItem w t = filter_ (filterPredicate t) w
  where
    filter_ :: (a -> Bool) -> ListWidget a -> ListWidget a
    filter_ predicate widget = (update widget $ filter predicate $ getList widget) `setPosition` 0

-- | Rotate elements of given list by given number.
--
-- >>> rotate 3 [0..10]
-- [3,4,5,6,7,8,9,10,0,1,2]
rotate :: Int -> [a] -> [a]
rotate n l = drop n l ++ take n l

searchForward :: (a -> Bool) -> ListWidget a -> ListWidget a
searchForward predicate widget = maybe widget (setPosition widget) match
  where
    match = findFirst predicate shiftedList
    -- rotate list, to get next match from current position
    shiftedList = rotate n enumeratedList
      where
        n = getPosition widget + 1
        enumeratedList = zip [0..] $ getList widget

searchBackward :: (a -> Bool) -> ListWidget a -> ListWidget a
searchBackward predicate widget = maybe widget (setPosition widget) match
  where
    match = findFirst predicate shiftedList
    -- rotate list, to get next match from current position
    shiftedList = reverse $ rotate n enumeratedList
      where
        n = getPosition widget
        enumeratedList = zip [0..] $ getList widget

findFirst :: (a -> Bool) -> [(Int, a)] -> Maybe Int
findFirst predicate list = case matches of
  (n, _):_  -> Just n
  _         -> Nothing
  where
    matches = filter predicate_ list
      where
        predicate_ (_, y) = predicate y

searchItem :: Searchable a => ListWidget a -> SearchOrder -> String -> ListWidget a
searchItem w Forward  t = searchForward  (searchPredicate t) w
searchItem w Backward t = searchBackward (searchPredicate t) w

tryMatch :: Eq a => ListWidget a -> a -> Maybe (ListWidget a)
tryMatch lw c = setPosition lw `fmap` findFirst (==c) (zip [0..] $ getList lw)

data SearchPredicate = Search | Filter

searchPredicate :: Searchable a => String -> a -> Bool
searchPredicate = searchPredicate_ Search

filterPredicate :: Searchable a => String -> a -> Bool
filterPredicate = searchPredicate_ Filter

searchPredicate_ :: Searchable a => SearchPredicate -> String -> a -> Bool
searchPredicate_ predicate "" _ = onEmptyTerm predicate
  where
    onEmptyTerm Search = False
    onEmptyTerm Filter = True
searchPredicate_ _ term item = all (\term_ -> any (isInfixOf term_) tags) terms
  where
    tags = map (map toLower) (searchTags item)
    terms = words $ map toLower term

------------------------------------------------------------------------
-- move

setPosition :: ListWidget a -> Int -> ListWidget a
setPosition widget pos = widget { getPosition = newPosition, getViewPosition = newViewPosition }
  where
    newPosition     = clamp 0 listLength pos
    listLength      = getListLength widget
    viewPosition    = getViewPosition widget
    minViewPosition = newPosition - (getViewSize widget - 1)
    newViewPosition = max minViewPosition $ min viewPosition newPosition

moveFirst :: ListWidget a -> ListWidget a
moveFirst l = setPosition l 0

moveLast :: ListWidget a -> ListWidget a
moveLast l = setPosition l $ getListLength l - 1

moveUp :: ListWidget a -> ListWidget a
moveUp l = setPosition l (getPosition l - 1)

moveDown :: ListWidget a -> ListWidget a
moveDown l = setPosition l (getPosition l + 1)

scroll :: Int -> ListWidget a -> ListWidget a
scroll n l = l {getViewPosition = newViewPosition, getPosition = newPosition}
  where
    newViewPosition = clamp 0 (getListLength l) (getViewPosition l + n)
    newPosition     = clamp newViewPosition (newViewPosition + getViewSize l) (getPosition l)

select :: ListWidget a -> Maybe a
select l =
  if getListLength l > 0
    then Just $ getList l !! getPosition l
    else Nothing

setMarked :: ListWidget a -> Maybe Int -> ListWidget a
setMarked w x = w { getMarked = x }

render :: (Renderable a) => ListWidget a -> Render Ruler
render l = do
  let listLength      = getListLength l
      viewSize        = getViewSize l
      viewPosition    = getViewPosition l
      currentPosition = getPosition l

  when (listLength > 0) $ do

    let list            = take viewSize $ drop viewPosition $ getList l

    let putLine (y, element) = addLine y 0 (renderItem element)
    mapM_ putLine $ zip [0..] list

    let cursorPosition = currentPosition - viewPosition
    chgat cursorPosition [Reverse] MainColor

    forM_ (getMarked l) $ \marked -> do
      let y = marked - viewPosition
      when (0 <= y && y < viewSize) $ do
        let attr = if y == cursorPosition then [Bold, Reverse] else [Bold]
        chgat y attr MainColor

  let positionIndicator
        | listLength > 0 = Just (succ currentPosition, listLength)
        | otherwise      = Nothing

  return $ Ruler rulerText positionIndicator (visible listLength viewSize viewPosition)

  where
    rulerText = maybe "" breadcrumbs (getParent l)
    breadcrumbs list = case getParent list of
      Just p  -> breadcrumbs p ++ " > " ++ this
      Nothing -> this
      where
        this = maybe "" (toPlainText . renderItem) (select list)
