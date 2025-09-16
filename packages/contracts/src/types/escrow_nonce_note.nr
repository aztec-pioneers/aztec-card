use aztec::{
    macros::notes::note,
    oracle::random::random,
    prelude::AztecAddress,
    protocol_types::traits::{Deserialize, Serialize},
};

#[note]
#[derive(Eq, Serialize, Deserialize)]
pub struct EscrowNonceNote {
    owner: AztecAddress,
    nonce: u128,
    randomness: Field,
}

impl EscrowNonceNote {
    pub fn new(
        owner: AztecAddress,
        nonce: u128,
    ) -> Self {
        EscrowNonceNote {
            owner,
            nonce,
            randomness: unsafe { random() },
        }
    }
}