contract;

abi Demo {
    #[storage(read_write)]
    fn demo();
}

struct DynStruct { // A struct of dynamic size.
    vec: Vec<u64>,
    txt: String,
}

impl AbiEncode for DynStruct {
    fn abi_encode(&self, buffer: Buffer) -> Buffer {
        let mut buffer = self.vec.abi_encode(buffer);
        buffer = self.txt.abi_encode(buffer);

        buffer
    }
}

impl AbiDecode for DynStruct {
    fn abi_decode(ref mut buffer: BufferReader) -> Self {
        let vec = Vec::<u64>::abi_decode(buffer);
        let txt = String::abi_decode(buffer);

        DynStruct {
            vec,
            txt,
        }
    }
}

storage {
    //--
    // For the sake of example, in the below examples we assume that the `Vec` and `String` have
    // the presented `const fn from(...)` functions implemented via the `From` trait.
    // But in general, any const eval expression that returns `Vec`, or `String`, or `DynStruct` can
    // apear on the RHS of `:=`.
    //--
    //--
    // The usage patterns and the capabilities of `StorageEncodedBox` are the same as the
    // ones of the `StorageBox`. Essentially, to support types that require encoding, the only
    // thing that developers need to do, is to replace the `StorageBox` with the `StorageEncodedBox`.
    //--
    box_1: StorageEncodedBox<DynStruct> := Struct::default(),
    box_2: StorageEncodedBox<DynStruct> := Struct { vec: Vec::from([1, 2, 3]), txt: String::from("text") },
    //--
    // `box_3` encodes (on write) and decodes (on read) the entire boxed vector of `DynStruct`!
    // When boxed as such, it is not possible to access only individual elements of the stored vector.
    // This will be explained in the documentation, together with the hint that the inteded storage structure
    // is actually very likely the `StorageVec<StorageEncodedBox<DynStruct>>` demonstrated below.
    //--
    box_3: StorageEncodedBox<Vec<DynStruct>> := Vec::from([const_create_struct(1, "abc"), const_create_struct(2, "cdf")]),

    vec_of_encoded_val_1: StorageVec<StorageEncodedBox<String>> := [String::from("abc"), String::from("cdf")],
    vec_of_encoded_val_2: StorageVec<StorageEncodedBox<DynStruct>> := [
        DynStruct::default(),
        DynStruct { vec: Vec::from([1, 2, 3]), txt: String::from("text") },
        some_const_fn_that_creates_struct(true, "abc"),
    ],

    vec_of_vec_1: StorageVec<StorageVec<StorageEncodedBox<DynStruct>>> := [
        [],
        [DynStruct::default()],
        [
            DynStruct::default(),
            DynStruct { vec: Vec::from([1, 2, 3]), txt: String::from("text") },
            some_const_fn_that_creates_struct(true, "abc"),
        ]
    ],

    map_01: StorageMap<str[3], StorageVec<StorageMap<u64, StorageVec<StorageEncodedBox<DynStruct>>>>> := [
        ("abc", [
            (11, [DynStruct::default(), const_create_struct(1, "abc")]),
            (22, []),
            (33, [some_const_fn_that_creates_struct(true, DynStruct::default()]),
        ]),
        ("def", [
            (111, [DynStruct::default(), const_create_struct(1, "abc")]),
            (222, [DynStruct { vec: Vec::from([1, 2, 3]), txt: String::from("text") }]),
            (333, [some_const_fn_that_creates_struct(true, "abc")]),
        ]),
    ],
}

impl Demo for Contract {
    #[storage(read_write)]
    fn demo() {
        //--
        // `StorageEncodedBox` is used in the code in the same way as the `StorageBox`.
        // For examples, see `demo_contract_basic_storage.sw`.
        //--
    }
}
