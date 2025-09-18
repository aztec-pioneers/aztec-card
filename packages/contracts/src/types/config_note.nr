use aztec::{
    macros::notes::note,
    oracle::random::random,
    prelude::AztecAddress,
    protocol_types::traits::{Deserialize, Serialize},
};
use std::embedded_curve_ops::EmbeddedCurvePoint;

/**
 * Static configuration of a Card Escrow contract. Sets commonly used variables
 * in a single note to reduce slot usage. Is immutable after contract constructor
 * is called.
 */
#[note]
#[derive(Eq, Serialize, Deserialize)]
pub struct ConfigNote {
    // required field for note - will always be the escrow contract itself
    owner: AztecAddress,
    // the ARC20 token that the operator will debit to pay for card usage
    token_address: AztecAddress,
    // the user who deposits funds and spends via the card
    user_address: AztecAddress,
    // the operator who issues the card and debits from the escrow when the card is used
    operator_address: AztecAddress,
    // the operator's schnorr pubkey, used to privately authorize otherwise contentious functions
    operator_pubkey_x: Field,
    operator_pubkey_y: Field,
    // required field for a note - blinding factor
    randomness: Field,
}

impl ConfigNote {
    /** Creates a new config note */
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

    /** Return the operator's schnorr pubkey in the expected type for verification */
    pub fn operator_schnorr_pubkey(self) -> EmbeddedCurvePoint {
        EmbeddedCurvePoint {
            x: self.operator_pubkey_x,
            y: self.operator_pubkey_y,
            is_infinite: false
        }
    }
}
