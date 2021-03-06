module Data.WebsiteContent
    ( WebsiteContent (..)
    , StackRelease (..)
    , Post (..)
    , loadWebsiteContent
    ) where

import ClassyPrelude.Yesod
import Text.Markdown (markdown, msXssProtect, msAddHeadingId)
import Data.GhcLinks
import Data.Aeson (withObject)
import Data.Yaml
import System.FilePath (takeFileName)

data WebsiteContent = WebsiteContent
    { wcHomepage :: !Html
    , wcAuthors  :: !Html
    , wcOlderReleases :: !Html
    , wcGhcLinks :: !GhcLinks
    , wcStackReleases :: ![StackRelease]
    , wcPosts :: !(Vector Post)
    }

data Post = Post
  { postTitle :: !Text
  , postSlug :: !Text
  , postAuthor :: !Text
  , postTime :: !UTCTime
  , postDescription :: !Text
  , postBody :: !Html
  }

loadWebsiteContent :: FilePath -> IO WebsiteContent
loadWebsiteContent dir = do
    wcHomepage <- readHtml "homepage.html"
    wcAuthors <- readHtml "authors.html"
    wcOlderReleases <- readHtml "older-releases.html" `catchIO`
                    \_ -> readMarkdown "older-releases.md"
    wcGhcLinks <- readGhcLinks $ dir </> "stackage-cli"
    wcStackReleases <- decodeFileEither (dir </> "stack" </> "releases.yaml")
        >>= either throwIO return
    wcPosts <- loadPosts (dir </> "posts") `catchAny` \e -> do
      putStrLn $ "Error loading posts: " ++ tshow e
      return mempty
    return WebsiteContent {..}
  where
    readHtml fp = fmap (preEscapedToMarkup . decodeUtf8 :: ByteString -> Html)
                $ readFile $ dir </> fp
    readMarkdown fp = fmap (markdown def
                        { msXssProtect   = False
                        , msAddHeadingId = True
                        } . fromStrict . decodeUtf8)
               $ readFile $ dir </> fp

loadPosts :: FilePath -> IO (Vector Post)
loadPosts dir =
     fmap (sortBy (\x y -> postTime y `compare` postTime x))
   $ runConduitRes
   $ sourceDirectory dir
  .| concatMapC (stripSuffix ".md")
  .| mapMC loadPost
  .| sinkVector
  where
    loadPost :: FilePath -> ResourceT IO Post
    loadPost noExt = handleAny (\e -> throwString $ "Could not parse " ++ noExt ++ ".md: " ++ show e) $ do
      bs <- readFile $ noExt ++ ".md"
      let slug = pack $ takeFileName noExt
          text = filter (/= '\r') $ decodeUtf8 bs
      (frontmatter, body) <-
        case lines text of
          "---":rest ->
            case break (== "---") rest of
              (frontmatter, "---":body) -> return (unlines frontmatter, unlines body)
              _ -> error "Missing closing --- on frontmatter"
          _ -> error "Does not start with --- frontmatter"
      case Data.Yaml.decodeEither' $ encodeUtf8 frontmatter of
        Left e -> throwIO e
        Right mkPost -> return $ mkPost slug $ markdown def
          { msXssProtect = False
          , msAddHeadingId = True
          } $ fromStrict body

instance (slug ~ Text, body ~ Html) => FromJSON (slug -> body -> Post) where
  parseJSON = withObject "Post" $ \o -> do
    postTitle <- o .: "title"
    postAuthor <- o .: "author"
    postTime <- o .: "timestamp"
    postDescription <- o .: "description"
    return $ \postSlug postBody -> Post {..}

data StackRelease = StackRelease
    { srName :: !Text
    , srPattern :: !Text
    }
instance FromJSON StackRelease where
    parseJSON = withObject "StackRelease" $ \o -> StackRelease
        <$> o .: "name"
        <*> o .: "pattern"
