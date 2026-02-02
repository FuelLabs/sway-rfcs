contract;

abi Demo {
    #[storage(read_write)]
    fn demo();
}

type StVecOfU64 = StorageVec<StorageBox<u64>>;
type StPairOfStVecOfU64 = StoragePair<StVecOfU64, StVecOfU64>;

storage {
    vec_1: StVecOfU64 := [11, 22, 33],
    vec_2: StVecOfU64 := [44, 55, 66],

    pair_1: StPairOfStVecOfU64 := ([0, 0, 0], [1, 1, 1]),
    pair_2: StPairOfStVecOfU64 := ([], []),

    map_1: StorageMap<str[3], StVecOfU64> := [
        ("abc", [1, 2, 3]),
        ("def", [11, 22, 33]),
        ("ghi", [111, 222, 333]),
    ]

    //--
    // Storage references can be used in storage configurations.
    // They can reference other storage elements, or their parts.
    //
    // This is possible, because `Storage::new` used to instantiate
    // storage elements is a `const fn`. So is the `as_ref` which
    // returns the `StorageRef<Self>`.
    //--
    vec_of_refs: StorageVec<StorageRefBox<StVecOfU64>> := [
        StorageRef::Null,
        storage.vec_1.as_ref(), // We can reference the whole `StorageVec` but not individual elements,
                                // because `StorageVec::get` is not a `const fn`.
        storage.pair_1.first().as_ref(), // `StoragePair::first` is a `const fn`.
        storage.map_1.get("abc").as_ref(), // `StorageMap::get` is a `const fn`.
        StorageRef::Ref(some_const_fn_that_returns_the_storage_key_of_the_referenced_storage()),
    ],

    pair_of_refs: StoragePair<StorageRefBox<StVecOfU64>, StorageRefBox<StVecOfU64>> := (StorageRef::Null, StorageRef::Null),
}

impl Demo for Contract {
    #[storage(read_write)]
    fn demo() {
        //--
        // Storage references can be tested for null or dereferenced
        // to access the referenced storage elements.
        //--
        assert(vec_of_refs.get(0).read().is_null());

        match vec_of_refs.get(1).read().try_deref() {
            Some(vec_of_u64) => {
                assert_eq(vec_of_u64.get(0).read(), 11);
            }
            _ => { },
        }

        //--
        // They can also be set to reference storage elements.
        // To obtain a `StorageRef` from a `Storage`, use `Storage::as_ref`.
        //--
        assert(pair_of_refs.first().read().is_null());

        pair_of_refs.set_first(pair_1.snd().as_ref());

        let referenced_vec = pair_of_refs.first().read().deref();
        assert_eq(referenced_vec.get(0).read(), 1);
    }
}
