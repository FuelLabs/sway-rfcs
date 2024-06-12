//--
// This example discuss details of the proposed API design guidelines
// in respect to:
//  - handling uninitialized `Storage`.
//  - handling semantic errors in operations.
//  - handling special options like, e.g., skipping checks for performance.
//
// For the complete `Storage` implementation of the `StorageVec` and its other aspects
// see `sway-libs/storage/storage_vec.sw`.
//--

impl<T> StorageVec<T> where T: Storage {
    const fn get_element_self_key(self_key: &StorageKey, element_index: u64) -> StorageKey {
        //--
        // Calcualte the self key of the element stored at `element_index`.
        // `self_key` is the self key of the [StorageVec].
        // For the sample implementation, see `sway-libs/storage/storage_vec.sw`.
        //--
    }

    //--
    // Getting length can fail if the `StorageVec` is not initialized.
    // Therefore, we provide the `try` method.
    // `try` methods return `Option`.
    //--
    #[storage(read)]
    pub fn try_len(&self) -> Option<u64> {
        storage::low_level_api::read::<u64>(self.self_key)
    }

    //--
    // For every `try` method, we provide its "non-try" equivalent,
    // which just unwraps the result of the `try` methods.
    // Therefore, it reverts if the `StorageVec` is uninitialized.
    //--
    #[storage(read)]
    pub fn len(&self) -> u64 {
        self.try_len().unwrap()
    }

    //--
    // For each `Storage`, we give an uninitialize storage a semantic
    // meaning. In the case of the `StorageVec`, we treat the uninitialized
    // `StorageVec` as an empty `StorageVec`.
    //
    // This means that the `push` cannot fail, and therefore, we provide only
    // the `push` method, an not a `try_push`.
    //--
    #[storage(read_write)]
    pub fn push(&mut self, value: &T::Value) {
        let len = self.try_len().unwrap_or(0);

        // Store the value.
        let element_self_key = Self::get_element_self_key(&self.self_key, len);
        T::init(element_self_key, value);

        // Store the new length.
        storage::low_level_api::write(self.self_key, len + 1);
    }

    //--
    // `pop` is a much more difficult example.
    // Same as with `push` and other methods, we treat an uninitialized
    // `StorageVec` as an empty vector.
    //
    // The additional challange here is providing the possibility to deep clear
    // the popped element. This surely requires an separate method because of
    // an additional trait constraint `T: DeepClearStorage`.
    //
    // In this case, the guideline is to provide a `<name>_<special_behavior>()`
    // equivalent, `pop_deep_clear()`.
    //
    // So we will have a `pop` and a `pop_deep_clear` methods.
    //
    // Note that this approach, `<name>_<special_behavior>()`, does not scale
    // well if we want to combine several "special behaviors" in one call.
    // However, in the storage API design, we do not expect such cases, or at
    // least not a considerable number of them.
    //
    // And in the case they do appear, the guideline is to have a single distinguished
    // method with a "special behavior" that accepts additional parameters.
    // E.g., let's say that we want to `<operation>_deep_clear` with certains checks
    // being optional. A possible method would look like:
    //
    //  fn <operation>_deep_clear(&mut self, checked: bool)
    //--
    #[storage(read_write)]
    pub fn pop(&mut self) -> bool {
        let len = self.try_len().unwrap_or(0);

        if len <= 0 {
            return false;
        }

        //--
        // Just store the new length, without deep clearing the value.
        //--
        storage::low_level_api::write(self.self_key, len - 1);
    }

    #[storage(read_write)]
    pub fn pop_deep_clear(&mut self) -> bool where T: DeepClearStorage {
        let len = self.try_len().unwrap_or(0);

        if len <= 0 {
            return false;
        }

        let element_self_key = Self::get_element_self_key(&self.self_key, len - 1);
        T::new(element_self_key).deep_clear();

        storage::low_level_api::write(self.self_key, len - 1);
    }

    //--
    // Same as above, `get` treats the uninitialized `StorageVec` as empty.
    //
    // The important consequence of that decision, to treat an initialized vector
    // as empty is, that we do not distinguish between "technical" errors, those
    // coming from reading uninitialized storge, and "semantic" errors, those coming
    // from, e.g., reading out of bounds.
    //
    // This means that we will, following the guideline given above, have a
    // `try_get` and a `get` method, where actually the `try_get` corresponds to
    // the `get` method in the current implementation of the `StorageVec`, that
    // returns `Option`.
    //--
    #[storage(read)]
    pub fn try_get(&self, element_index) -> Option<T> {
        if self.try_len().unwrap_or(0) <= index {
            return None;
        }

        let element_self_key = Self::get_element_self_key(&self.self_key, element_index);
        Some(T::new(element_self_key))
    }

    #[storage(read)]
    pub fn get(&self, element_index) -> T {
        self.try_get(element_index).unwrap()
    }

    //--
    // Another important aspect of `get` is a possibility to have a special behavior
    // that is not the default one. Concretely, providing the possibility to skip
    // the costly bound check. According to the `<name>_<special_behavior>` guideline
    // given above, we will have the `get_unchecked` method.
    //
    // Note that in this case, there is no `try_get_unchecked` because ignoring the
    // boundary check also removes the possibility that the `get` fails.
    //
    // In a general case, we should also provide the `try_<name>_<special_behavior>` method.
    //--
    #[storage(read)]
    pub fn get_unchecked(&self, element_index) -> T {
        let element_self_key = Self::get_element_self_key(&self.self_key, element_index);
        T::new(element_self_key)
    }

    //--
    // Clear always means a semantic clear with a minimum storage manipulation. In the case
    // of the `StorageVec`, it is sufficient to set its length to zero, or to clear
    // the slot at its self key.
    //
    // Note that we do not have the `clear_deep_clear` equivalent. We expect here to use
    // the `deep_clear` method directly.
    //--
    pub fn clear(&mut self) {
        storage::low_level_api::write(self.self_key, 0);
    }

    /* ... Other `StorageVec` methods that follow the same API design guidelines. ... */
}
