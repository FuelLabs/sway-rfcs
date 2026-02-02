// This example shows how to apply the proposed API design guidelines
// on the `StoragePair`.
//
// For API design quidelines, see `api-design/storage_vec.sw` and `api-design/storage_encoded_box.sw`.
//
// For the complete `Storage` implementation of the `StoragePair` and its other aspects
// see `sway-libs/storage/storage_pair.sw`.
//--

impl<A, B> StoragePair<A, B> where A: Storage, B: Storage {
    const fn get_first_element_self_key(self_key: &StorageKey) -> StorageKey {
        //--
        // Returns the self key of the first element of the pair.
        // `self_key` is the self key of the `StoragePair`.
        // For the sample implementation, see `sway-libs/user-defined-libs/storage_vec.sw`.
        //--
    }

    /// Returns the self key of the second element of the pair.
    /// `self_key` is the self key of the [StoragePair].
    const fn get_snd_element_self_key(self_key: &StorageKey) -> StorageKey {
        //--
        // Returns the self key of the second element of the pair.
        // `self_key` is the self key of the `StoragePair`.
        // For the sample implementation, see `sway-libs/user-defined-libs/storage_vec.sw`.
        //--
    }

    //--
    // The below methods consistently apply the API guidelines
    // explained in detail in `api-design/storage_vec.sw` and `api-design/storage_encoded_box.sw`.
    //--

    #[storage(read)]
    pub const fn first(&self) -> A {
        A::new(Self::get_first_element_self_key(&self.self_key))
    }

    #[storage(read)]
    pub const fn snd(&self) -> B {
        B::new(Self::get_snd_element_self_key(&self.self_key))
    }

    #[storage(read_write)]
    pub fn set_first(&mut self, value: &A::Value) -> A {
        let first_element_self_key = Self::get_first_element_self_key(&self.self_key);
        A::init(&first_element_self_key, value)
    }

    #[storage(read_write)]
    pub fn set_first_deep_clear(&mut self, value: &A::Value) -> A where A: DeepClearStorage {
        let first_element_self_key = Self::get_first_element_self_key(&self.self_key);
        self.set_element_deep_clear::<A>(&first_element_self_key, value)
    }

    #[storage(read_write)]
    pub fn set_snd(&mut self, value: &B::Value) -> B {
        let snd_element_self_key = Self::get_snd_element_self_key(&self.self_key);
        A::init(&snd_element_self_key, value)
    }

    #[storage(read_write)]
    pub fn set_snd_deep_clear(&mut self, value: &B::Value) -> B where B: DeepClearStorage {
        let snd_element_self_key = Self::get_snd_element_self_key(&self.self_key);
        self.set_element_deep_clear::<B>(&first_element_self_key, value)
    }

    #[storage(read_write)]
    fn set_element_deep_clear<TElement>(element_self_key: &StorageKey, value: &TElement::Value) -> TElement where TElement: DeepClearStorage {
        match TElement::internal_layout() {
            // If the size of the element is fixed, we will just overwrite the current content, if any.
            ContinuousOfKnownSize(_) => { },
            // Otherwise, we must first deep clear the content.
            _ => TElement::new(element_self_key).deep_clear(),
        }

        TElement::init(element_self_key, value)
    }

    #[storage(read_write)]
    pub fn clear(&mut self) {
        /* ...
           Clear only the slot at the `self_key` by calling the `storage::low_level_api::clear::<T>(<key>)`
           where `T` is a type that guarantees a single slot gets cleared.
           
           TODO-DISCUSSION: See the discussion on clearing API in the `low_level_api.sw`.
           ...
        */
    }

    /* ... Other `StoragePair` methods that follow the same API design guidelines. ... */
}
