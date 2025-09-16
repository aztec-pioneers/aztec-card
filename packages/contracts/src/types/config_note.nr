use aztec::{
    macros::notes::note,
    oracle::random::random,
    prelude::AztecAddress,
    protocol_types::traits::{Deserialize, Serialize},
};
use std::embedded_curve_ops::EmbeddedCurvePoint;

#[note]
#[derive(Eq, Serialize, Deserialize)]
pub struct ConfigNote {
    owner: AztecAddress,
    token_address: AztecAddress,
    user_address: AztecAddress,
    operator_address: AztecAddress,
    operator_pubkey_x: Field,
    operator_pubkey_y: Field,
    randomness: Field,
}

impl ConfigNote {
    pub fn new(
        owner: AztecAddress,
        token_address: AztecAddress,
        user_address: AztecAddress,
        operator_address: AztecAddress,
        operator_pubkey_x: Field,
        operator_pubkey_y: Field
    ) -> Self {
        ConfigNote {
            owner,
            token_address,
            user_address,
            operator_address,
            operator_pubkey_x,
            operator_pubkey_y,
            randomness: unsafe { random() },
        }
    }

    pub fn operator_schnorr_pubkey(&self) -> EmbeddedCurvePoint {
        EmbeddedCurvePoint {
            x: self.operator_pubkey_x,
            y: self.operator_pubkey_y,
            is_infinite: false
        }
    }
}
