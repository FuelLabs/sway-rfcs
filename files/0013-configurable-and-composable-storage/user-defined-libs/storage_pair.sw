//--
// This module demonstrates how to implement a custome `Storage` type.
//--

pub struct StoragePair<A, B> where A: Storage, B: Storage {
    self_key: StorageKey,
}

impl<A, B> Storage for StoragePair<A, B> where A: Storage, B: Storage {
    type Value = (A::Value, B::Value);
    type Config = (A::Config, B::Config);

    const fn new(self_key: &StorageKey) -> Self {
        Self {
            self_key: *self_key
        }
    }

    const fn internal_get_config(self_key: &StorageKey, pair: &(A::Value, B::Value)) -> Self::Config {
        let first_element_self_key = Self::get_first_element_self_key(self_key);
        let snd_element_self_key = Self::get_snd_element_self_key(self_key);

        (A::internal_get_config(&first_element_self_key, &pair.0), B::internal_get_config(&snd_element_self_key, &pair.1))
    }

    const fn internal_layout() -> StorageLayout {
        use std::storage::StorageLayout::*;
        match (A::internal_layout(), B::internal_layout()) {
            // If both sizes are known, we pack the elements one after another
            // and provide the known overall size.
            (ContinuousOfKnownSize(a), ContinuousOfKnownSize(b)) => ContinuousOfKnownSize(a + b),
            // If the first element has a known size, we continue storing the
            // second element in consecutive remaining words and consecutive slots.
            (ContinuousOfKnownSize(_), _) => Continuous,
            _ => Scattered,
        }
    }

    const fn self_key(&self) -> StorageKey {
        self.self_key
    }

    #[storage(write)]
    fn init(self_key: &StorageKey, pair: &(A::Value, B::Value)) -> Self {
        let first_element_self_key = Self::get_first_element_self_key(self_key);
        let snd_element_self_key = Self::get_snd_element_self_key(self_key);

        A::init(&first_element_self_key, &pair.0);
        B::init(&snd_element_self_key, &pair.1);

        Self::new(self_key)
    }
}

impl<A, B> StoragePair<A, B> where A: Storage, B: Storage {
    /// Returns the self key of the first element of the pair.
    /// `self_key` is the self key of the [StoragePair].
    const fn get_first_element_self_key(self_key: &StorageKey) -> StorageKey {
        // The first element is always stored at the pair self key.
        *self_key
    }

    /// Returns the self key of the second element of the pair.
    /// `self_key` is the self key of the [StoragePair].
    const fn get_snd_element_self_key(self_key: &StorageKey) -> StorageKey {
        use std::storage::StorageLayout::*;
        match (A::internal_layout(), B::internal_layout()) {
            (ContinuousOfKnownSize(first_size), _) => {
                //--
                // The elements are packed and aligned to optimize slot usage and storage access.
                // Here we calculate the second element storage key based on the size of
                // the first element.
                // Note that the calculation will be a const eval one.
                //--
                StorageKey::new(<result of the calculation>);
            },
            _ => {
                // The second element is stored in its own slot.
                StorageKey::new(__sha256((*self_key, 0)), 0);
            }
        }
    }

    #[storage(read)]
    pub const fn first(&self) -> A {
        A::new(Self::get_first_element_self_key(&self.self_key))
    }

    #[storage(read)]
    pub const fn snd(&self) -> B {
        B::new(Self::get_snd_element_self_key(&self.self_key))
    }

    #[storage(write)]
    pub fn set_first(&mut self, value: &A::Value) -> A {
        let first_element_self_key = Self::get_first_element_self_key(&self.self_key);
        A::init(&first_element_self_key, value)
    }

    #[storage(write)]
    pub fn set_snd(&mut self, value: &B::Value) -> B {
        let snd_element_self_key = Self::get_snd_element_self_key(&self.self_key);
        A::init(&snd_element_self_key, value)
    }

    /* ... Oher `StoragePair` methods. ... */
}

impl<A, B> DeepReadStorage for StoragePair<A, B> where A: DeepReadStorage, B: DeepReadStorage {
    /// Returns the entire content stored within the [StoragePair],
    /// or `None` if any of the [StoragePair] elements is uninitialized.
    ///
    /// This method can result in multiple storage reads and must,
    /// therefore, be used with caution and only if the entire content
    /// is actually needed.
    #[storage(read)]
    fn try_deep_read(&self) -> Option<Self::Value> {
        let first_element_self_key = Self::get_first_element_self_key(self_key);
        let snd_element_self_key = Self::get_snd_element_self_key(self_key);

        let first_element_value = match A::new(first_element_self_key).try_deep_read() {
            Some(value) => value,
            None => return None,
        };

        let snd_element_value = match A::new(snd_element_self_key).try_deep_read() {
            Some(value) => value,
            None => return None,
        };

        Some((first_element_value, snd_element_value))
    }
}