- Feature Name: Multi-signer Scripts
- Start Date: 2023-04-07
- RFC PR: [FuelLabs/sway-rfcs#0000](https://github.com/FuelLabs/sway-rfcs/pull/001)
- Sway Issue: [FueLabs/sway#0000](https://github.com/FuelLabs/sway/issues/001)

# Summary

[summary]: #summary

This RFC proposes a new "Tx" struct/enum to be used in scripts to allow for atomic execution of bundle-like scripts.

Allowing programmers to insert external transactions into their own scripts for atomic execution without any additional security assumptions can allow for a much more decentralised and secure MEV environment where both users and searchers benefit greatly, whilst also unlocking previously unseen types of MEV.

# Motivation

[motivation]: #motivation

The current script features allow programmers to execute multiple transactions atomically, but it is limited to one party and cannot be extended to allow for atomic execution of transactions from multiple parties. Allowing insertion of third party transactions into scripts would remove the need for centralised block proposers who have privileged access to signed orderflow.

# Guide-level explanation

[guide-level-explanation]: #guide-level-explanation

The "Tx" enum comes in two variants, "Signed" and "Unsigned". The Signed variant represents a Transaction which has already been signed, and the Unsigned variant represents an intent of a transaction, without actually being signed yet.

A script including a Signed Tx may execute the signed tx once at any point in their script, creating their own contract calls before and/or after the external tx. This can be used to arbitrage price changes, provide just in time liquidity, or other sorts of MEV tactics.

A script including an Unsigned Tx may also execute the unsigned tx at any point in their script, however, before submitting the script to the blockchain, it must be sent to the third party so they can sign and fulfill their intent, or else the script will revert.

Eg.

```sway
script;

fn main(third_party_tx: Tx) {
    // Arbitrary actions before execution of third party tx
    ...

    // Execute the third party tx
    third_party_tx.execute()

    // Arbitrary actions after execution of third party tx
    ...
}
```

You could also inspect the third party tx in order to make decisions based on the third party tx

```sway
script;

use exchange_abi::Exchange;
use std::constants::ZERO_B256;

fn main(third_party_tx: Tx) {
    let exchange_contract_address = 0x9299da6c73e6dc03eeabcce242bb347de3f5f56cd1c70926d76526d7ed199b8b;
    let caller = abi(Exchange, exchange_contract_address);

    // Retrieve calls made to the given caller by the external tx
    let calls: Vec<Calls> = third_party_tx.inspect(caller.swap);

    // Amount swapped by third party tx in the last call to swap (assuming there is a call to swap)
    let swap_call = calls.pop().unwrap();
    let amount = swap_call.coins;
    let asset_a = swap_call.asset_id;
    let asset_b = swap_call.arguments.asset_b;

    // Executing the external tx
    third_party_tx.execute()

    // Copy trading the external tx
    caller.swap {
        gas: 10000,
        coins: amount,
        asset_id: asset_a,
    }(asset_b);
}
```

# Reference-level explanation

[reference-level-explanation]: #reference-level-explanation

As shown in the previous example, programmers can insert an external tx programmatically by making it a parameter of the script and even inspect the tx, by calling the inspect method, and passing in an abi's function as an argument. If there are any calls to the same contract address with the same abi, and calling the mentioned function, then the inspect method will return a list of all the calls made to that function. The programmer can then use the returned values to advise their future logic.

This gives the programmer all the information they need about the external transaction to effectively make use of it, in a easy and intuitive way.

# Drawbacks

[drawbacks]: #drawbacks

As Fuel will start off with a single sequencer model, MEV can be effectively regulated by the Fuel labs org without any additional features.

# Rationale and alternatives

[rationale-and-alternatives]: #rationale-and-alternatives

The current alternatives are 

-Regular scripts. While scripts already allow atomic execution of multiple contract calls, they are not an effective alternative for bundles as external transactions have no representation in scripts.
-Bundles. Transactions inside bundles can easily be unbundled and exploited by privileged actors such as validators.

Without representation of external transactions inside scripts, searchers would have to have to send bundles of scripts to validators for execution, where validators can easily ignore some scripts and replace them with their own, exploiting the searcher. This sort of attack has happened multiple times in the past.

Representing external transactions in scripts allows a searcher to sign an entire script at once, where tampering with the contents of the script would render it invalid, safegaurding the searcher from unbundling attacks or uncle bandit attacks.

# Prior art

[prior-art]: #prior-art

Flashbots introduced the concept of bundles, starting a new MEV ecosystem where searchers could send bundles of transactions to the private mempool maintained by flashbots. Unforunately due to the nature of ethereum works, once a bundle is submitted in a block, it can be unbundled by anyone, meaning if a bundle lands in a block that later becomes an uncle block, these now seperate transactions can be reused by anyone in their own bundles. Validators can also easily unbundle transactions before submitting them in a block.

# Unresolved questions

[unresolved-questions]: #unresolved-questions

-Best api for representation of external transactions. The examples I have given have a syntax that could be considered by some to be half baked.
-How would a programmer programmatically make scripts. Currently scripts must be written and compiled manually, with no way to add additional data at runtime, such as the external transaction data.
-How do you effectively fulfill an intent. Would sending over a signed version of the external tx be enough? Or does the third party need to sign the whole new script.
-Is script inspection possible with the current tooling?

# Future possibilities

[future-possibilities]: #future-possibilities

Allow retail users to earn money from selling their own orderflow. A user can signal their intent to for example buy BTC by signing a tx for a USD -> BTC swap, the wallet could automatically recognize this and send out a unsigned tx intent to searchers, who can then build a mev extraction script with it, and send out a bid for it (orderflow auction). Highest bidder gets the signed tx for their script, user and searcher both make no security assumptions and have atomic execution regardless. Wallets could even disallow bids with frontrunning/sandwiching etc with special script inspection.

These sorts of scripts could unlock new types of MEV which route revenue to the users instead of validators. For examples, a wallet could add a feature which allows users to auction out their own orderflow. A user could signal their intent to sell BTC by signing a tx for a BTC -> USD swap, then the wallet could automatically recognise this and sent out an unsigned tx intent to searchers, who could bid on the right to use the intent in their script. Winning bid recieves the signed tx which the searcher can use to extract MEV. Auction proceedings go to the user as the user is the only person with the power to fulfill the intent, as they have the keys to sign the intent. Neither the user nor the searcher make any security assumptions as there is no unbundling risk to the searchers and the user can inspect the bid scripts and reject any scripts that result in a loss to the user, (by detecting frontrunning or other harmful forms of MEV).