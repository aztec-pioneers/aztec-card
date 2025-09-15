use aztec::{
    macros::notes::note,
    oracle::random::random,
    prelude::AztecAddress,
    protocol_types::traits::{Deserialize, Serialize},
};

#[note]
#[derive(Eq, Serialize, Deserialize)]
pub struct SpentAmountEpochNote {
    owner: AztecAddress,
    spent_amount: u128,
    randomness: Field,
}

impl SpentAmountEpochNote {
    pub fn new(
        owner: AztecAddress,
        spent_amount: u128
    ) -> Self {
        SpentAmountEpochNote {
            owner,
            spent_amount,
            randomness: unsafe { random() },
        }
    }

    // pub fn nullifier(owner: Field, blinding: Field, epoch: Field) -> Field {
    //     Poseidon2::hash([
    //         owner,
    //         blinding,
    //         epoch
    //     ])
    // }
}
