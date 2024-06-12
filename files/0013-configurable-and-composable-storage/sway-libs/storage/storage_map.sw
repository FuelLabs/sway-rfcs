//--
// We assume here that slices will have const eval implementations for:
//  - `[T] += [T] -> [T]`: slice contatenation.
//  - `[T] += T   -> [T]`: extending a slice with an element.
//--
pub struct StorageMap<K, V> where K: Hash, V: Storage {
    self_key: StorageKey,
}

//--
// The key of a `StorageMap` cannot be a `Storage`.
// We forbid this by negative impls, essentially saying that
// a StorageMap whose key is a Storage is not a Storage itself.
//--
//--
// TODO-DISCUSSION: Should we in general prevent that Storage implements Hash?
//                  Or on the contrary allow it and allow here that `K` can be
//                  a `Storage` as long as it implements `Hash`?
//                  It is difficult, though, to imagine a `Storage` that implements
//                  a `const Hash`.
//--
impl<K, V> !Storage for StorageMap<K, V> where K: Storage + Hash, V: Storage { }

impl<K, V> Storage for StorageMap<K, V> where K: Hash, V: Storage {
    type Value = [(K, V::Value)];
    type Config = [V::Config];

    const fn new(self_key: &StorageKey) -> Self {
        Self {
            self_key: *self_key
        }
    }

    const fn internal_get_config(self_key: &StorageKey, elements: &[(K, V::Value)]) -> Self::Config {
        let elements_config: [V::Config] = [];
        let mut i = 0;
        while i < elements.len() {
            let element_self_key = Self::get_element_self_key(&self_key, elements[i].0);
            elements_config += T::internal_get_config(&element_self_key, &elements[i].1);

            i += 1;
        }

        elements_config
    }

    const fn internal_layout() -> StorageLayout {
        StorageLayout::Scattered
    }

    const fn self_key(&self) -> StorageKey {
        self.self_key
    }

    #[storage(read_write)]
    fn init(self_key: &StorageKey, elements: &[(K, V::Value)]) -> Self {
        let mut i = 0;
        while i < elements.len() {
            let element_self_key = Self::get_element_self_key(&self_key, elements[i].0);
            T::init(element_self_key, &elements[i].1);

            i += 1;
        }

        Self::new(self_key)
    }
}

//--
// For the detailed API design guidelines see the examples in the `api-design`.
//--

impl<K, V> StorageMap<K, V> where K: Hash, V: Storage {
    /// Returns the self key of the element stored at `element_key`.
    /// `self_key` is the self key of the [StorageVec].
    const fn get_element_self_key(self_key: &StorageKey, element_key: K) -> StorageKey {
        StorageKey::new(__sha256((*self_key, element_key)), 0);
    }

    #[storage(read_write)]
    pub fn insert(&mut self, key: K, value: &V:Value) -> V {
        let element_self_key = Self::get_element_self_key(&self_key, key);
        V:init(element_self_key, value)
    }

    #[storage(read)]
    pub const fn get(&self, key: K) -> V {
        let element_self_key = Self::get_element_self_key(&self_key, key);
        V:new(element_self_key)
    }
}