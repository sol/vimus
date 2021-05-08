module Option (getOptions) where

import           Paths_vimus (version)
import           Data.Version (showVersion)

import           Data.Maybe
import           Data.List
import           Control.Monad
import           Text.Printf (printf)
import           System.Environment (getArgs, getProgName)
import           System.Exit (exitSuccess, exitFailure)
import           System.IO (hPutStr, stderr)
import           System.Console.GetOpt

data Option = Help
            | Version
            | IgnoreVimusrc
            | OptionHost String
            | OptionPort String
            deriving (Show, Eq)

hostHelp :: String
hostHelp = intercalate "\n"
  [ "The host to connect to; if not given, the value"
  , "of the environment variable MPD_HOST is checked"
  , "before defaulting to localhost.  To use a"
  , "password, provide a value of the form"
  , "`password@host'."
  ]

portHelp :: String
portHelp = intercalate "\n"
  [ "The port to connect to; if not given, the value"
  , "of the environment variable MPD_PORT is checked"
  , "before defaulting to 6600."
  ]

options :: [OptDescr Option]
options = [
    Option []     ["help"]            (NoArg  Help             ) "Display this help and exit."
  , Option []     ["version"]         (NoArg  Version          ) "Display version and exit."
  , Option ['h']  ["host"]            (ReqArg OptionHost "HOST") hostHelp
  , Option ['p']  ["port"]            (ReqArg OptionPort "PORT") portHelp
  , Option []     ["ignore-vimusrc"]  (NoArg  IgnoreVimusrc    ) "Do not source ~/.config/vimus/vimusrc on startup."
  ]


getOptions :: IO (Maybe String, Maybe String, Bool)
getOptions = do

  (opts, args, errors) <- getOpt Permute options `liftM` getArgs

  when (Help `elem` opts) $ do
    progName <- getProgName
    putStr $ usageInfo (printf "Usage: %s [options]\n\nOPTIONS" progName) options
    exitSuccess

  when (Version `elem` opts) $ do
    progName <- getProgName
    putStrLn (progName ++ " " ++ showVersion version)
    exitSuccess

  unless (null errors) $
    exitTryHelp $ head errors

  unless (null args) $
    exitTryHelp $ printf "unexpected argument `%s'\n" $ head args

  let port = listToMaybe . reverse $ [ option | OptionPort option <- opts ]
  let host = listToMaybe . reverse $ [ option | OptionHost option <- opts ]
  let ignoreVimusrc = IgnoreVimusrc `elem` opts

  return (host, port, ignoreVimusrc)


exitTryHelp :: String -> IO a
exitTryHelp message = do
  progName <- getProgName
  hPutStr stderr $ printf "%s: %sTry `%s --help' for more information.\n" progName message progName
  exitFailure
