// This example shows how to apply the proposed API design guidelines
// on the `StorageEncodedBox`.
//
// For API design quidelines, see `api-design/storage_vec.sw`.
//
// For the complete `Storage` implementation of the `StorageEncodedBox` and its other aspects
// see `sway-libs/storage/storage_encoded_box.sw`.
//--

impl StorageEncodedBox<T> where T: AbiEncode + AbiDecode {
    //--
    // Reading can fail so we provide `try_read` and `read`.
    //--
    #[storage(read)]
    fn try_read(&self) -> Option<T> {
        let encoded_value = /* ...
           Read the length of the encoded value from the `self_key`
           and continue reading the `u8` content from the slots.
           If any of the reads fail, the `try_read` fails.

           The implementation uses `storage::low_level_api::read(<key>)`
           to actually read from the storage.
           ...
        */;

        Some(abi_decode::<T>(encoded_value))
    }

    #[storage(read)]
    fn read(&self) -> T {
        self.try_read().unwrap()
    }

    //--
    // Write cannot fail so we provide only `write`.
    //
    // Since the content can have a variable length, in case of writing,
    // the default implementation will just overwrite the old value,
    // potentially leaving parts of the old content in the storage
    // (if it was longer then the new value).
    //
    // Thus, to enable clearing of the old content, we provide the
    // `write_deep_clear` method.
    //--
    #[storage(write)]
    fn write(&mut self, value: &T) {
        let encoded_value = encode::<T>(value);

        /* ...
           Write the length of the `encoded_value` to the `self.self_key`
           and continue writing its packed `u8` content to that and
           the consecutive slots.

           Packing also means packing 8 `u8`s into a single `u64`
           and then those `u64`s into slots.

           The implementation uses `storage::low_level_api::write(<key>, <val>)`
           to actually write to the storage.
           ...
        */
    }

    #[storage(write)]
    fn write_deep_clear(&mut self, value: &T) {
        let encoded_value = encode::<T>(value);

        /* ...
           Write the new content, and clear the remaining parts of the old
           content, if any.
           ...
        */
    }

    //--
    // Clear always means a semantic clear with a minimum storage manipulation. In the case
    // of the `StorageEncodedBox`, it is sufficient to clear the slot at its self key.
    //
    // Note that we do not have the `clear_deep_clear` equivalent. We expect here to use
    // the `deep_clear` method directly.
    //--
    #[storage(write)]
    fn clear(&mut self) {
        /* ...
           Clear only the slot at the `self_key` by calling the `storage::low_level_api::clear::<T>(<key>)`
           where `T` is a type that guarantees a single slot gets cleared.
           
           TODO-DISCUSSION: See the discussion on clearing API in the `low_level_api.sw`.
           ...
        */
    }
}
