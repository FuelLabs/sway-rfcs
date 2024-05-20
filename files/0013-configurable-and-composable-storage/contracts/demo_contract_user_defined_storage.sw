contract;

abi Demo {
    #[storage(write)]
    fn demo();
}

struct Struct {
    x: u64,
    y: bool,
}

type StVecOfU64 = StorageVec<StorageBox<u64>>;
type StPairOfStVecOfU64 = StoragePair<StVecOfU64, StVecOfU64>;

storage {
    //--
    // Every user-defined `Storage` is fully compatible with SDK and all other storage types.
    // Implementing `Storage` automatically makes any `Storage` configurable and composable.
    //--
    pair_1: StoragePair<StorageBox<u64>, StorageEncodedBox<String>> := (123, String::from("text")),
    pair_2: StoragePair<StVecOfU64, StVecOfU64> := ([1, 2, 3], [11, 22, 33]),

    vec_of_pairs: StorageVec<StoragePair<StorageBox<Struct>, StVecOfU64>> := [
        (Struct { x: 0, y: true }, [1, 2, 3]),
        (Struct::default(), []),
        (Struct { x: 11, y: false }, [111, 222, 333]),
    ],

    map_of_pairs: StorageMap<str[3], StoragePair<StorageBox<Struct>, StVecOfU64>> := [
        ("abc", (Struct { x: 0, y: true }, [1, 2, 3])),
        ("def", Struct::default(), []),
        ("ghi", Struct { x: 11, y: false }, [111, 222, 333]),
    ],

    pair_of_pairs: StoragePair<StPairOfStVecOfU64, StPairOfStVecOfU64> := (
        ([1, 2, 3], [11, 22, 33]),
        ([4, 5, 6], [44, 55, 66])
    )
}

impl Demo for Contract {
    #[storage(write)]
    fn demo() {
        assert_eq(pair_1.first().read(), 123);

        pair_1.set_snd(String::from("other text"));
        assert_eq(pair_1.snd().read(), String::from("other text"));

        // Storage types can also be created and used in code without being declared in the storage.
        // We assume below that we've calculated the desired `slot` and the `offset` and got the storage key.
        let storage_key = get_storage_key( ... );

        let mut local_pair_1 = StoragePair::<StPairOfStVecOfU64, StPairOfStVecOfU64>::init(&storage_key,
            (([], []), ([], []))
        );
        
        local_pair_1.first().snd().push(123);

        let local_pair_1_value = local_pair_1.deep_read();
        asert_eq(local_pair_1_value, (([], [123]), ([], [])));
    }
}