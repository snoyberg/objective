module Control.Object.Stream where

import Data.Functor.Rep
import Data.Functor.Adjunction
import Control.Object.Object
import Data.Foldable as F
import Control.Applicative
import Data.Functor.Request

-- | For every adjunction f ⊣ g, we can "connect" @Object g m@ and @Object f m@ permanently.
($$) :: (Monad m, Adjunction f g) => Object g m -> Object f m -> m x
a $$ b = do
  (x, a') <- runObject a askRep
  ((), b') <- runObject b (unit () `index` x)
  a' $$ b'
infix 1 $$

-- | 'filter' for consumers.
filterL :: (Adjunction f g, Applicative m) => (Rep g -> Bool) -> Object f m -> Object f m
filterL p obj = Object $ \f -> if counit (tabulate p <$ f)
  then fmap (filterL p) `fmap` runObject obj f
  else pure (extractL f, filterL p obj)

mapL :: (Adjunction f g, Adjunction f' g', Functor m) => (Rep g' -> Rep g) -> Object f m -> Object f' m
mapL t = (^>>@) $ rightAdjunct $ \x -> tabulate (index (unit x) . t)

-- | Create a producer from a 'Foldable' container.
fromFoldable :: (Foldable t, Alternative m, Adjunction f g) => t (Rep g) -> Object g m
fromFoldable = F.foldr go $ Object $ const empty where
  go x m = Object $ \cont -> pure (index cont x, m)

-- TODO: filterR and mapR

mapR :: (Representable f, Representable g, Functor m) => (Rep f -> Rep g) -> Object f m -> Object g m
mapR t = (^>>@) $ \f -> tabulate (index f . t)

filterR :: (Representable f, Monad m) => (Rep f -> Bool) -> Object f m -> Object f m
filterR p obj = Object $ \f -> go f obj where
  go f o = do
    (x, o') <- runObject o askRep
    if p x
      then return (index f x, filterR p o')
      else go f o'

($$@) :: (Representable f, Representable g, Monad m) => Object f m -> Object (Request (Rep f) (Rep g)) m -> Object g m
obj $$@ pro = Object $ \g -> do
  (x, obj') <- runObject obj askRep
  (a, pro') <- runObject pro $ Request x (index g)
  return (a, obj' $$@ pro')

(@$$) :: (Adjunction f g, Adjunction f' g', Monad m) => Object (Request (Rep g') (Rep g)) m -> Object f m -> Object f' m
pro @$$ obj = Object $ \f' -> do
  let (a, f_) = splitL f'
  (x, pro') <- runObject pro $ Request (counit (askRep <$ f_)) id
  ((), obj') <- runObject obj $ unit () `index` x
  return (a, pro' @$$ obj')