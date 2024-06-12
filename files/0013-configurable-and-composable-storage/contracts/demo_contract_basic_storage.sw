contract;

abi Demo {
    #[storage(read_write)]
    fn demo();
}

struct Struct {
    x: u64,
    y: bool,
}

storage {
    //--
    // Compiler calls `internal_make_config` here and passes it the `:=`'s RHS and the compiler-generated `StorageKey`.
    //
    // There is no any special syntax on the RHS. It's just a regular Sway expression that can occure anywhere
    // else in Sway that creates a value of the type specified in the declaration of the LHS.
    //--
    //--
    // TODO-DISCUSSION: Is there any better proposal for the "configured with" operator, than `:=`?
    //                  We do not want to use `=` here because it implies assignment and initialization.
    //                  Also, we want to use the same operator when configuring configurables.
    //--
    box_1: StorageBox<u64> := 0,
    box_2: StorageBox<u64> := the_meaning_of_life(),

    box_3: StorageBox<Struct> := Struct::default(),
    box_4: StorageBox<Struct> := Struct { x: 11, y: false },
    box_4: StorageBox<Struct> := some_const_fn_that_creates_struct(true, Struct { x: 22, y: true }, "abc"),

    vec_of_val_1: StorageVec<StorageBox<u64>> := [],
    vec_of_val_2: StorageVec<StorageBox<u64>> := [1, 2, 3, 4, 5],
    vec_of_val_3: StorageVec<StorageBox<Struct>> := [
        Struct::default(),
        Struct { x: 11, y: false },
        some_const_fn_that_creates_struct(true, Struct { x: 22, y: true }, "abc"),
    ],

    vec_of_vec_1: StorageVec<StorageVec<StorageBox<Struct>>> := [
        [],
        [Struct::default()],
        [
            Struct::default(),
            Struct { x: 11, y: false },
            some_const_fn_that_creates_struct(true, Struct { x: 22, y: true }, "abc"),
        ]
    ],

    map_01: StorageMap<str[3], StorageVec<StorageMap<u64, StorageVec<StorageBox<Struct>>>>> := [
        ("abc", [
            (11, [Struct::default(), Struct { x: 11, y: false }]),
            (22, []),
            (33, [some_const_fn_that_creates_struct(true, Struct { x: 22, y: true }, "abc"), Struct::default()]),
        ]),
        ("def", [
            (111, [Struct::default(), Struct { x: 111, y: true }]),
            (222, [Struct::new_false(222)]),
            (333, [some_const_fn_that_creates_struct(true, Struct { x: 22, y: true }, "abc")]),
        ]),
    ],

    //--
    // If developers are not interested in configuring storage elements in the code, but just defining them,
    // they can omit the `:=` operator if the type expected on the RHS implements `core::default::Default` trait.
    //--
    default_built_in: StorageBox<u64>,                                     // Same as `default_built_in: StorageBox<u64> := 0`.
    default_struct: StorageBox<Struct>,                                    // `Struct` implements `core::default::Default`.
    default_storage_vec: StorageVec<StorageBox<u64>>,                      // Slices implement `Default` and the default is an empty slice `[]`.
    default_storage_map: StorageMap<str[3], StorageVec<StorageBox<u64>>>,  // Slices implement `Default` and the default is an empty slice `[]`.
}

impl Demo for Contract {
    #[storage(read_write)]
    fn demo() {
        //-----------------------------------

        // When creating the `box_1` the compiler calls `new` and passes the self-generated `StorageKey`.
        let x = storage.box_1.read();

        // `storage` elements are mutable by default.
        // Important because we properly model mutability on the `Storage` methods.
        // E.g., `fn write(&mut self)`.
        storage.box_1.write(&1111);

        // Storage types can also be created and used in code without being declared in the storage.
        // We assume below that we've calculated the desired `slot` and the `offset` and got the storage key.
        let storage_key = get_storage_key( ... );

        let local_box_1 = StorageBox::<b256>::init(storage_key, &b256::zero());
        assert_eq(local_box_1.read(), 0x0000000000000000000000000000000000000000000000000000000000000000);

        // We properly model mutability, so the `local_box_2` must
        // be mutable if we want to write to the storage through it.
        let mut local_box_2 = StorageBox::init(storage_key, &true);
        assert_eq(local_box_2.read(), true);

        local_box_2.write(false);
        assert_eq(local_box_2.read(), false);

        //-----------------------------------

        assert_eq(storage.vec_of_val_1.len(), 0);

        storage.vec_of_val_1.push(&1111);
        assert_eq(storage.vec_of_val_1.len(), 1);

        let popped = storage.vec_of_val_1.pop();
        assert_eq(popped, true);

        storage.vec_of_val_1.push(&2222);

        // The result of `get` is always the stored `Storage`.
        let val = storage.vec_of_val_1.get(0).read();
        assert_eq(val, 2222);

        // `StorageVec` implements `DeepReadStorage` and provides
        // optimized access if the entire stored value is needed.
        // Should be used rarely and with caution.
        let content = storage.vec_of_val_1.deep_read();
        assert_eq(content, [2222])

        storage.vec_of_vec_1.push(&[]);
        storage.vec_of_vec_1.push(&[Struct { x: 11, y: true }, Struct { x: 22, y: false }]);

        let val = storage.vec_of_vec_1.get(1).get(0).read(); // Accessing `vec_of_vec_1[1][0]`.
        assert_eq(val, Struct::default());

        let storage_key = get_storage_key( ... );

        let mut local_vec_of_vec_of_vec_1 = StorageVec<StorageVec<StorageVec<StorageBox<u64>>>>::init(storage_key, &[
            [],
            [[]],
            [[], []],
            [[11, 22, 33], [33, 22, 11]]
        ]);

        // The overall Storage API prohibits semantically wrong usage.
        // The desired composition semantics that implies ownership of the
        // stored data is imposed by the API.
        //
        // E.g., `StorageVec::push` does not accept the contained storage
        // as the type but rather the value that needs to be contained.
        //
        // This prohibits non-sensical usage like:
        //
        // let vec_of_vec_a = StorageVec<StorageVec<StorageBox<u6>>>::init(...);
        // let vec_of_vec_b = StorageVec<StorageVec<StorageBox<u6>>>::init(...);
        // let element_of_a = a.get(0);
        // vec_of_vec_of_b.push(element_of_a);
        //
        // `StorageVec` which is contained in `a` cannot be contained in `b`!
        //
        // `StorageRef` allows referencing storage. For the demo see: demo_contract_storage_refs.sw.

        local_vec_of_vec_of_vec_1.push(&[[11, 22, 33], [33, 22, 11]]);

        //-----------------------------------

        let storage_key = get_storage_key( ... );

        let local_map_1 = StorageMap<str[3], StorageVec<StorageMap<u64, StorageVec<StorageBox<Struct>>>>>::init(storage_key, &[]);
        local_map_1.insert("123", &[
            ("000", []),
            ("111", [
                (111, [Struct::default()]),
            ]),
        ]);

        let storage_key = get_storage_key( ... );

        let local_map_2 = StorageMap<str[3], StorageVec<StorageMap<u64, StorageVec<StorageBox<Struct>>>>>::init(storage_key, &[
            ("abc", [
                (11, [Struct::default(), Struct { x: 11, y: false }]),
                (22, []),
                (33, [some_const_fn_that_creates_struct(true, Struct { x: 22, y: true}, "abc"), Struct::default()]),
            ]),
            ("def", [
                (111, [Struct::default(), Struct { x: 111, y: true }]),
                (222, [Struct::new_false(222)]),
                (333, [some_const_fn_that_creates_struct(true, Struct { x: 22, y: true}, "abc")]),
            ]),
        ]);

        let val = local_map_2.get("abc").get(0).get(11).get(0).read();
        assert_eq(val, Struct::default());
    }
}