//--
// `StorageRefBox` is just a type alias for the `StorageBox<StorageRef<TStorage>>`.
// To declare it as such, we need a possibility to declare type aliases with generic parameters
// and trait constraints.
//
// Note that we can always implement it without type aliases with generic parameters,
// by simply replicating the implementation of the `StorageBox`.
//--
pub type StorageRefBox<TStorage> = StorageBox<StorageRef<TStorage>> where TStorage: Storage;
