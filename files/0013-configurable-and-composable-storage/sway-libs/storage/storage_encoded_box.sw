/// Atomic [Storage] type that encodes the value it stores
/// using the value's type implementation of [AbiEncode].
///
/// The [StorageEncodedBox] is used for storing dynamic types
/// like, e.g., `Vec` or `String`, or any user-defined type that is not
/// [core::marker::Serializable] but implements [AbiEncode]
/// and [AbiDecode].
pub struct StorageEncodedBox<T> where T: AbiEncode + AbiDecode {
    self_key: StorageKey,
}

//--
// `StorageEncodedBox` is another one atomic storage type.
// The idea and the reasoning behind atomic storage types
// as well as negative impls is explained in the `storage_box.sw`.
//--
impl<T> !Storage for StorageEncodedBox<T> where T: Storage { }

//--
// TODO-DISCUSSION: See discussion on `Serializable` in the `storage_box.sw`.
//--
use core::marker::Serializable;

//--
// TODO-DISCUSSION: Shell we forbid encoded-boxing serializable types and thus force
//                  them to be boxed in `StorageBox` or should this only be a compiler warning?
//                  Essentially, if a type is `Serializable` encoding it unnecessarily
//                  is a huge waste of computational and storage resources.
//--

impl<T> !Storage for StorageEncodedBox<T> where T: Serializable { }

impl<T> Storage for StorageEncodedBox<T> where T: AbiEncode + AbiDecode {
    type Value = T;
    //--
    // The assumption is, once we get slices, `raw_slice` will dissapear. 
    // Today this would be a `StorageConfig<raw_slice>`.
    //--
    type Config = StorageConfig<[u8]>; 

    const fn new(self_key: &StorageKey) -> Self {
        Self {
            self_key: *self_key
        }
    }

    const fn internal_get_config(self_key: &StorageKey, value: &T) -> StorageConfig<T> {
        StorageConfig {
            self_key: *self_key,
            //--
            // Note that we assume that the `encode` will be defined as:
            //   pub const fn encode<T>(item: &T) -> [u8]
            //--
            value: encode::<T>(value),
        }
    }

    const fn internal_layout() -> StorageLayout {
        StorageLayout::Continuous
    }

    const fn self_key(&self) -> StorageKey {
        self.self_key
    }

    #[storage(write)]
    fn init(self_key: &StorageKey, value: &T) -> Self {
        let mut new_box = Self::new(self_key);
        new_box.write(value);
        new_box
    }
}

//--
// For the detailed API design guidelines see the examples in the `api-design`.
//--

impl StorageEncodedBox<T> where T: AbiEncode + AbiDecode {
    /// Reverts if the [StorageEncodedBox] is uninitialized.
    #[storage(read)]
    fn read(&self) -> T {
        self.try_read().unwrap()
    }

    #[storage(read)]
    fn try_read(&self) -> Option<T> {
        let encoded_value = /* ...
           Read the length of the encoded value from the `self_key`
           and continue reading the `u8` content from the slots.
           If any of the reads fail, the `try_read` fails.

           The implementation uses `storage::internal::read(<key>)`
           to actually read from the storage.
           ...
        */;

        Some(abi_decode::<T>(encoded_value))
    }

    #[storage(write)]
    fn write(&mut self, value: &T) {
        let encoded_value = encode::<T>(value);

        /* ...
           Write the length of the `encoded_value` to the `self.self_key`
           and continue writing its packed `u8` content to that and
           the consecutive slots.

           Packing also means packing 8 `u8`s into a single `u64`
           and then those `u64`s into slots.

           The implementation uses `storage::internal::write(<key>, <val>)`
           to actually write to the storage.
           ...
        */
    }

    #[storage(write)]
    fn clear(&mut self) {
        /* ...
           Clear only the slot at the `self_key` by calling the `storage::internal::clear::<T>(<key>)`
           where `T` is a type that guarantees a single slot gets cleared.
           
           TODO-DISCUSSION: See the discussion on clearing API in the `internal.sw`.
           ...
        */
    }
}

impl<T> DeepReadStorage for StorageEncodedBox<T> where T: AbiEncode + AbiDecode {
    #[storage(read)]
    fn try_deep_read(&self) -> Option<T> {
        self.try_read()
    }
}

impl<T> DeepClearStorage for StorageEncodedBox<T> where T: AbiEncode + AbiDecode {
    #[storage(write)]
    fn deep_clear(&mut self) -> Option<T> {
        /* ...
           Read the length of the `encoded_value` and calculate the
           optimal (minimal) number of calls to `storage::internal::clear(<key>)`
           needed to clear the entire value from the storage.
           
           TODO-DISCUSSION: See the discussion on clearing API in the `internal.sw`.
           ...
        */
    }
}