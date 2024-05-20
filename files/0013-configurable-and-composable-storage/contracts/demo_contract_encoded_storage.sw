contract;

abi Demo {
    #[storage(write)]
    fn demo();
}

struct Struct {
    vec: Vec<u64>,
    txt: String,
}

impl AbiEncode for Struct {
    fn abi_encode(&self, buffer: Buffer) -> Buffer {
        let mut buffer = self.vec.abi_encode(buffer);
        buffer = self.txt.abi_encode(buffer);

        buffer
    }
}

impl AbiDecode for Struct {
    fn abi_decode(ref mut buffer: BufferReader) -> Self {
        let vec = Vec::<u64>::abi_decode(buffer);
        let txt = String::abi_decode(buffer);

        Struct {
            vec,
            txt,
        }
    }
}

storage {
    //--
    // For the sake of example, in the below examples we assume that the `Vec` and `String` have
    // the presented `const fn from(...)` functions implemented via the `From` trait.
    // But in general, any const eval expression that returns `Vec`, or `String`, or `Struct` can
    // apear on the RHS of `:=`.
    //--
    //--
    // The usage patterns and the capabilities of `StorageEncodedBox` are the same as the
    // ones of the `StorageBox`. Essentially, to support types that require encoding, the only
    // thing that developers need to do is replace `StorageBox` with `StorageEncodedBox`.
    //--
    box_1: StorageEncodedBox<Struct> := Struct::default(),
    box_2: StorageEncodedBox<Struct> := Struct { vec: Vec::from([1, 2, 3]), txt: String::from("text") },
    box_3: StorageEncodedBox<Vec<Struct>> := Vec::from([const_create_struct(1, "abc"), const_create_struct(2, "cdf")]),

    vec_of_encoded_val_1: StorageVec<StorageEncodedBox<Vec<bool>> := [Vec::from([true, false, true]), Vec::default(), Vec::from([true])],
    vec_of_encoded_val_2: StorageVec<StorageEncodedBox<String>> := [String::from("abc"), String::from("cdf")],
    vec_of_encoded_val_3: StorageVec<StorageEncodedBox<Struct>> := [
        Struct::default(),
        Struct { vec: Vec::from([1, 2, 3]), txt: String::from("text") },
        some_const_fn_that_creates_struct(true, "abc"),
    ],

    vec_of_vec_1: StorageVec<StorageVec<StorageEncodedBox<Struct>>> := [
        [],
        [Struct::default()],
        [
            Struct::default(),
            Struct { vec: Vec::from([1, 2, 3]), txt: String::from("text") },
            some_const_fn_that_creates_struct(true, "abc"),
        ]
    ],

    map_01: StorageMap<str[3], StorageVec<StorageMap<u64, StorageVec<StorageEncodedBox<Struct>>>>> := [
        ("abc", [
            (11, [Struct::default(), const_create_struct(1, "abc")]),
            (22, []),
            (33, [some_const_fn_that_creates_struct(true, Struct::default()]),
        ]),
        ("def", [
            (111, [Struct::default(), const_create_struct(1, "abc")]),
            (222, [Struct { vec: Vec::from([1, 2, 3]), txt: String::from("text") }]),
            (333, [some_const_fn_that_creates_struct(true, "abc")]),
        ]),
    ],
}

impl Demo for Contract {
    #[storage(write)]
    fn demo() {
        //--
        // `StorageEncodedBox` is used in the code in the same way as the `StorageBox`.
        // For examples, see `demo_contract_basic_storage.sw`.
        //--
    }
}
