//--
// Unlike the current `StorageKey`, the new one becomes a plain struct that holds
// the `slot` and the `offset`. There will be no storage type impls on it.
//--
pub struct StorageKey {
    slot: b256,
    offset: u64,
}

impl StorageKey {
    pub const fn new(slot: b256, offset: u64) -> Self {
        Self {
            slot,
            offset
        }
    }
}

/// Defines how a concrete [Storage] implementation places
/// its stored values within the storage, relative to the
/// given self key of the storage.
pub enum StorageLayout {
    /// The values are scattered within the storage and
    /// can be on arbitrary storage slots, unrelated to
    /// the self key.
    Scattered: (),
    /// The values are stored starting from the self key
    /// in a continuous sequence of consecutive storage
    /// slots. The size that the stored value occupies is
    /// not know and can vary.
    Continuous: (),
    /// The values are stored starting from the self key
    /// in a continuous sequence of consecutive storage
    /// slots. The size that the stored value occupies is
    /// known and fixed.
    ContinuousOfKnownSize: u64,
}

//--
// Functions and methods marked with `internal` are used only by the `Storage`
// trait implementors and by the compiler.
//
// TODO-DISCUSSION: Should we introduce a language feature here and not rely on a naming convention hack?
//                  E.g., a language feature for something like `pub(impl) fn`.
//                  The naming convention solution is convenient and simple, but still bloats the list
//                  of methods/functions availabe in a scope.
//--
pub trait Storage {
    /// The type of the value that can be stored in this [Storage].
    type Value;
    /// The type that describes how this [Storage] stores its internal data and the
    /// stored value within the storage.
    ///
    /// This type can be only one of the valid combinations of [StorageConfig<TValue>]s described below.
    ///
    /// Sway compiler will use this type to properly configure storage slots for the elements declared
    /// in `storage` declarations.
    ///
    /// `Config` type is defined recursively as:
    ///
    /// ```ignore
    /// <Config> := StorageConfig<TValue>
    ///             | [<Config>]
    ///             | (<Config>, ...);
    /// ```
    ///
    /// Where `[<Config>]` represents a slice of `Config`s and `(<Config>, ...)` a tuple of arbitrary
    /// many `Config`s.
    type Config;

    /// Creates a new [Storage] that is not initialized.
    ///
    /// To create a new initialized [Storage], use the [Storage::init] constructor.
    //--
    //  Compiler will call this function in the storage element access.
    //  E.g. in `storage.x` to create `x`.
    //
    //  Note that `new` is a `const` function. This allows us to use storage
    //  elements when configuring other storage elements, e.g., to obtain
    //  storage references within storage configuration. For an example,
    //  see `demo_contract_storage_references.sw`.
    //--
    const fn new(self_key: &StorageKey) -> Self;

    /// Provides a configuration information for configuring an instance of this [Storage].
    /// The [Storage] will be located at the `self_key` and has to store `values`.
    ///
    /// This function should be used only when developing a custom
    /// [Storage] and should never occur in contract code.
    //--
    //  Compiler will call this function when generating storage slots.
    //  It will pass the `self_key` that it has generated for the storage element
    //  and the `value` will be the the const evaluated configuration value
    //  defined at the RHS of the `:=` operator.
    //--
    const fn internal_make_config(self_key: &StorageKey, value: &Self::Value) -> Self::Config;

    /// The [StorageLayout] of this [Storage].
    ///
    /// This function should be used only when developing a custom
    /// [Storage] and should never occur in contract code.
    const fn internal_layout() -> StorageLayout;

    /// The self key of this [Storage].
    const fn self_key(&self) -> StorageKey;

    /// Creates a new [Storage] that is initialized to the `value`.
    /// The created [Storage] is located at the `self_key` and stores the `value`.
    //--
    // TODO-DISCUSSION: Should we pass the `&Self::Value` here or just the `Self::Value`?
    //                  This is a general question that is not only related to the storage API.
    //                  It will become relevant when we introduce references in the standard library.
    //                  It is about avoiding copying data but not having the move semantics.
    //                  How much can we optimize? How to avoid heap allocations in case of
    //                  using references? Etc.
    //--
    #[storage(read_write)]
    fn init(self_key: &StorageKey, value: &Self::Value) -> Self;
} {
    const fn as_ref(&self) -> StorageRef<Self> {
        StorageRef::<Self>::Ref(self.self_key())
    }
}

/// Provides information to the compiler, during the configuration of the `storage`,
/// at which `storage_key` to store the `value`.
///
/// `TValue` cannot be a [Storage] or a [StorageConfig].
///
/// This struct should be used only when developing a custom
/// [Storage] and should never occur in contract code.
pub struct StorageConfig<TValue>
{
    pub storage_key: StorageKey,
    pub value: TValue,
}

/// Stores a reference to a [Storage] of type `TStorage`.
///
/// To create a [StorageRef::Ref] use [Storage::as_ref].
///
/// To create a null reference, use [StorageRef::Null].
///
/// Internally, a [StorageRef] stores the storage key
/// of the referenced storage entity.
///
/// [StorageRef] requires two storage slots to store a reference.
/// Consider using other, less storage consuming, approaches to "reference"
/// storage entities. E.g., if they are stored in a [StorageVec], consider
/// "referencing" them by storing their indices as "references".
//--
// This type is a type safe wrapper around `StorageKey` that
// ensures we are always referencing and dereferencing a
// proper `TStorage` type.
//--
pub enum StorageRef<TStorage> where TStorage: Storage {
    Null: (),
    Ref: StorageKey,
}

impl<TStorage> StorageRef<TStorage> where TStorage: Storage {
    /// Reverts if the [StorageRef] is [StorageRef::Null].
    fn deref(&self) -> TStorage {
        self.try_deref().unwrap()
    }

    const fn try_deref(&self) -> Option<TStorage> {
        match self {
            Self::Null => None,
            Self::Ref(storage_key) => Some(TStorage::new(storage_key)),
        }
    }

    const fn is_null(&self) -> bool {
        match self {
            Self::Null => true,
            _ => false,
        }
    }
}

/// A [Storage] that supports reading and retrieving its entire stored value.
pub trait DeepReadStorage: Storage {
    /// Returns the entired value stored in the [Storage],
    /// or `None` if the [Storage] is uninitialized.
    ///
    /// Composable storage types usually offer specialized
    /// methods for accessing parts of the stored value.
    /// Retrieving the entire stored value should be used
    /// only if the entire value is actually needed.
    ///
    /// Not all storage types can retrieve the value
    /// they store. E.g., a [StorageMap] is not aware of
    /// all the elements stored and require access by
    /// key to individual elements.
    ///
    /// Retrieving the entire stored value can require
    /// high amout of storage reads for certain storage
    /// types. Therefore, this method must always be
    /// used with care and only if the entire value is
    /// actually needed.
    #[storage(read)]
    fn try_deep_read(&self) -> Option<Self::Value>;
} {
    #[storage(read)]
    fn deep_read(&self) -> Self::Value {
        self.try_deep_read().unwrap()
    }
}

/// A [Storage] that supports removing its entire stored value
/// from the storage by uninitializing the storage slots which
/// were occupied by the stored value.
pub trait DeepClearStorage: Storage {
    /// Clears the entired value stored in the [Storage].
    ///
    /// This call always succeeds, even if the [Storage] is
    /// uninitialized.
    ///
    /// Composable storage types usually offer specialized
    /// methods for semantically clear the stored value.
    /// To clear semantically means that the value will be removed
    /// from the perspective of the storage type, but the
    /// occupied storage slots will not necessarily be uninitialized.
    ///
    /// E.g., semantically clearing a [StorageVec] could simply set the length
    /// of the vector to zero, without actually touching the stored
    /// elements.
    ///
    /// Clearing the entire stored value should be used
    /// only if clearing the entire value is actually needed.
    ///
    /// Not all storage types can clear the value
    /// they store. E.g., a [StorageMap] is not aware of
    /// all the elements stored and therefore cannot clear
    /// all of them.
    ///
    /// Clearing the entire stored value can require
    /// high amout of storage clears for certain storage
    /// types. Therefore, this method must always be
    /// used with care and only if clearing the entire value is
    /// actually needed.
    #[storage(read_write)]
    fn deep_clear(&mut self);
}
