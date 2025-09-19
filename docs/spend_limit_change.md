# Changing Spend Limits
Changing spend limits of an escrow is a potentially contentious action that can negatively impact the card operator if used maliciously. There are two API's available:
* Forced/ timelocked spend limit changes (using `prepare_forced_spend_limit_change()` and `finalize_forced_spend_limit_change()`), documented in the [timelock docs](./timelocks.md)
* Signed withdrawals (using `change_spend_limit()`) documented in the [signed operations docs](./signed_operations.md).

Diagrams for the general flow and explanations of how these operations occur are included in the docs linked above.

Spending limits are a critical part of governing how much an operator can withdraw when calling `spend()`. The spend limit is reset every epoch. The process by which spend limits occur is documented in detail in the ["Epochs" and "Spend Limits" section of the spending docs](./spends.md).

Every time the `spend()` function is called, it will retrieve the `SpendLimitNote` and check the amount. If a user wishes to change how much they can spend on their card, whether decreasing or increasing this limit, the `change_spend_limit` flow simply mutates the `SpendLimitNote`. The operator should monitor changes to this note and correspondingly update the amount that the user can spend from their card in a given day.

Almost all additional logic is either authentication of the caller, bumping nonces, or the timelocked/ signed flows for confirming a spend limit change - all of which has been documented elsewhere and does not need redundant explanation of.
