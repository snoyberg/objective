{-# LANGUAGE GADTs, Rank2Types #-}
module Control.Object.Instance where
import Control.Concurrent.STM.TMVar
import Control.Monad.STM
import Control.Object.Object
import Control.Monad.IO.Class
import Control.Monad
import Control.Monad.Catch (MonadMask, bracketOnError)

-- | TMVar-based instance
data Instance f g where
  InstRef :: TMVar (Object f g) -> Instance f g
  InstLmap :: (forall x. f x -> g x) -> Instance g h -> Instance f h
  InstRmap :: Instance f g -> (forall x. g x -> h x) -> Instance f h

instance HProfunctor Instance where
  (^>>@) = InstLmap
  {-# INLINE (^>>@) #-}
  (@>>^) = InstRmap
  {-# INLINE (@>>^) #-}

-- | Invoke a method with an explicit landing function.
invokeOn :: (MonadIO m, MonadMask m)
         => (forall x. g x -> m x) -> Instance f g -> f a -> m a
invokeOn m (InstRef v) f = bracketOnError
  (liftIO $ atomically $ takeTMVar v)
  (\obj -> liftIO $ atomically $ do
    _ <- tryTakeTMVar v
    putTMVar v obj)
  (\obj -> do
    (a, obj') <- m (runObject obj f)
    liftIO $ atomically $ putTMVar v obj'
    return a)
invokeOn m (InstLmap t i) f = invokeOn m i (t f)
invokeOn m (InstRmap i t) f = invokeOn (m . t) i f

-- | Invoke a method with an explicit landing function.
invokeOnSTM :: (forall x. g x -> STM x) -> Instance f g -> f a -> STM a
invokeOnSTM m (InstRef v) f = do
  obj <- takeTMVar v
  (a, obj') <- m (runObject obj f)
  putTMVar v obj'
  return a
invokeOnSTM m (InstLmap t i) f = invokeOnSTM m i (t f)
invokeOnSTM m (InstRmap i t) f = invokeOnSTM (m . t) i f

-- | Invoke a method, atomically.
(..-) :: Instance f STM -> f a -> STM a
(..-) i = invokeOnSTM id i
{-# INLINE (..-) #-}
infixr 3 ..-

-- | Invoke a method.
(.-) :: (MonadIO m, MonadMask m) => Instance f m -> f a -> m a
(.-) = invokeOn id
{-# INLINE (.-) #-}
infixr 3 .-

-- | Create a new instance.
new :: MonadIO m => Object f g -> m (Instance f g)
new = liftIO . atomically . newSTM
{-# INLINE new #-}

-- | Create a new instance, having it sitting on the current environment.
newSettle :: MonadIO m => Object f m -> m (Instance f m)
newSettle = new
{-# INLINE newSettle #-}

-- | Create a new instance.
newSTM :: Object f g -> STM (Instance f g)
newSTM = liftM InstRef . newTMVar
{-# INLINE newSTM #-}
