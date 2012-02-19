{-# LANGUAGE FlexibleInstances #-}
module Widget where

import Control.Monad.Trans (MonadIO)

import UI.Curses (Window)

import ListWidget (ListWidget)
import qualified ListWidget

class Widget a where
  render :: (MonadIO m) => Window -> a -> m ()
  title  :: a -> String

instance Widget (ListWidget s) where
  render window l = ListWidget.render l (ListWidget.getShow l) window

  title l = case ListWidget.getParent l of
    Just p  -> ListWidget.breadcrumbs p
    Nothing -> ""
