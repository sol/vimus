module Content where

import qualified Data.Map as Map

import qualified Network.MPD as MPD hiding (withMPD)

import qualified Song

import System.FilePath (takeFileName)
import Text.Printf (printf)
import ListWidget (Searchable, searchTags)

-- | Define a new Content type to replace MPD.LsResult

data Content = Dir MPD.Path | Song MPD.Song | PList MPD.Path

-- | Isomorphisms for Content <-> MPD.LsResult

toContent :: MPD.LsResult -> Content
toContent r = case r of
  MPD.LsFile song      -> Song song
  MPD.LsPlaylist list  -> PList list
  MPD.LsDirectory path -> Dir path

fromContent :: Content -> MPD.LsResult
fromContent c = case c of
  Song song  -> MPD.LsFile song
  PList list -> MPD.LsPlaylist list
  Dir path   -> MPD.LsDirectory path

-- | Show instance for Content

instance Show Content where
  show s = case s of
    Song  song -> printf "%s - %s - %s - %s" (Song.artist song) (Song.album song) (Song.track song) (Song.title song)
    Dir   path -> "[" ++ takeFileName path ++ "]"
    PList list -> "(" ++ takeFileName list ++ ")"

instance Searchable Content where
  searchTags item = case item of
    Dir   path -> [takeFileName path]
    PList path -> [takeFileName path]
    Song  song -> concat $ Map.elems $ MPD.sgTags song
