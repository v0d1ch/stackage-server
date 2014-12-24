module Types where

import ClassyPrelude.Yesod
import Data.BlobStore (ToPath (..), BackupToS3 (..))
import Text.Blaze (ToMarkup)
import Database.Persist.Sql (PersistFieldSql (sqlType))
import qualified Data.Text as T

newtype PackageName = PackageName { unPackageName :: Text }
    deriving (Show, Read, Typeable, Eq, Ord, Hashable, PathPiece, ToMarkup, PersistField, IsString)
instance PersistFieldSql PackageName where
    sqlType = sqlType . liftM unPackageName
newtype Version = Version { unVersion :: Text }
    deriving (Show, Read, Typeable, Eq, Ord, Hashable, PathPiece, ToMarkup, PersistField)
instance PersistFieldSql Version where
    sqlType = sqlType . liftM unVersion
newtype PackageSetIdent = PackageSetIdent { unPackageSetIdent :: Text }
    deriving (Show, Read, Typeable, Eq, Ord, Hashable, PathPiece, ToMarkup, PersistField)
instance PersistFieldSql PackageSetIdent where
    sqlType = sqlType . liftM unPackageSetIdent
newtype HackageView = HackageView { unHackageView :: Text }
    deriving (Show, Read, Typeable, Eq, Ord, Hashable, PathPiece, ToMarkup, PersistField, IsString)
instance PersistFieldSql HackageView where
    sqlType = sqlType . liftM unHackageView

data PackageNameVersion = PNVTarball !PackageName !Version
                        | PNVNameVersion !PackageName !Version
                        | PNVName !PackageName
    deriving (Show, Read, Typeable, Eq, Ord)

instance PathPiece PackageNameVersion where
    toPathPiece (PNVTarball x y) = concat [toPathPiece x, "-", toPathPiece y, ".tar.gz"]
    toPathPiece (PNVNameVersion x y) = concat [toPathPiece x, "-", toPathPiece y]
    toPathPiece (PNVName x) = toPathPiece x
    fromPathPiece t' | Just t <- stripSuffix ".tar.gz" t' =
        case T.breakOnEnd "-" t of
            ("", _) -> Nothing
            (_, "") -> Nothing
            (T.init -> name, version) -> Just $ PNVTarball (PackageName name) (Version version)
    fromPathPiece t = Just $
        case T.breakOnEnd "-" t of
            ("", _) -> PNVName (PackageName t)
            (T.init -> name, version) | validVersion version ->
                PNVNameVersion (PackageName name) (Version version)
            _ -> PNVName (PackageName t)
      where
        validVersion =
            all f
          where
            f c = (c == '.') || ('0' <= c && c <= '9')

data StoreKey = HackageCabal !PackageName !Version
              | HackageSdist !PackageName !Version
              | CabalIndex !PackageSetIdent
              | CustomSdist !PackageSetIdent !PackageName !Version
              | HackageViewCabal !HackageView !PackageName !Version
              | HackageViewSdist !HackageView !PackageName !Version
              | HackageViewIndex !HackageView
              | SnapshotBundle !PackageSetIdent
              | HaddockBundle !PackageSetIdent
    deriving (Show, Eq, Ord, Typeable)

instance ToPath StoreKey where
    toPath (HackageCabal name version) = ["hackage", toPathPiece name, toPathPiece version ++ ".cabal"]
    toPath (HackageSdist name version) = ["hackage", toPathPiece name, toPathPiece version ++ ".tar.gz"]
    toPath (CabalIndex ident) = ["cabal-index", toPathPiece ident ++ ".tar.gz"]
    toPath (CustomSdist ident name version) =
        [ "custom-tarball"
        , toPathPiece ident
        , toPathPiece name
        , toPathPiece version ++ ".tar.gz"
        ]
    toPath (HackageViewCabal viewName name version) =
        [ "hackage-view"
        , toPathPiece viewName
        , toPathPiece name
        , toPathPiece version ++ ".cabal"
        ]
    toPath (HackageViewSdist viewName name version) =
        [ "hackage-view"
        , toPathPiece viewName
        , toPathPiece name
        , toPathPiece version ++ ".tar.gz"
        ]
    toPath (HackageViewIndex viewName) =
        [ "hackage-view"
        , toPathPiece viewName
        , "00-index.tar.gz"
        ]
    toPath (SnapshotBundle ident) =
        [ "bundle"
        , toPathPiece ident ++ ".tar.gz"
        ]
    toPath (HaddockBundle ident) =
        [ "haddock"
        , toPathPiece ident ++ ".tar.xz"
        ]
instance BackupToS3 StoreKey where
    shouldBackup HackageCabal{} = False
    shouldBackup HackageSdist{} = False
    shouldBackup CabalIndex{} = True
    shouldBackup CustomSdist{} = True
    shouldBackup HackageViewCabal{} = False
    shouldBackup HackageViewSdist{} = False
    shouldBackup HackageViewIndex{} = False
    shouldBackup SnapshotBundle{} = True
    shouldBackup HaddockBundle{} = True

newtype HackageRoot = HackageRoot { unHackageRoot :: Text }
    deriving (Show, Read, Typeable, Eq, Ord, Hashable, PathPiece, ToMarkup)

class HasHackageRoot a where
    getHackageRoot :: a -> HackageRoot
instance HasHackageRoot HackageRoot where
    getHackageRoot = id
