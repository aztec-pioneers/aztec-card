import {
    AccountWallet,
    PXE,
    Fr,
    L1FeeJuicePortalManager,
    FeeJuicePaymentMethodWithClaim,
} from "@aztec/aztec.js";
import { getInitialTestAccountsManagers, getInitialTestAccountsWallets } from "@aztec/accounts/testing";
import {
    deployEscrowContract,
    deployTokenContractWithMinter,
    wad,
    depositToEscrow,
    createPXE,
    getFeeJuicePortalManager,
    TOKEN_METADATA,
    expectBalancePrivate,
    CardEscrowContract,
    TokenContract,
    setupAccountWithFeeClaim
} from "../src";

describe("Private Transfer Demo Test", () => {
    let userPXE: PXE;
    let operatorPXE: PXE;

    let minter: AccountWallet;
    let user: AccountWallet;
    let operator: AccountWallet;

    let escrowMasterKey: Fr;

    let escrow: CardEscrowContract;
    let usdc: TokenContract;

    let operatorFeeJuicePortalManager: L1FeeJuicePortalManager;

    const INITIAL_SPEND_LIMIT = wad(1000n, 6n);
    const MINT_AMOUNT = wad(10000n, 6n);

    beforeAll(async () => {
        // setup PXE connections
        userPXE = await createPXE();
        operatorPXE = await createPXE(1);

        // get PXE 1 accounts
        const wallets = await Promise.all(
            (await getInitialTestAccountsManagers(userPXE)).map(m => m.register())
        );
        minter = wallets[0];
        user = wallets[1];

        // deploy PXE2 account
        // NOTE: must allow two transactions to pass before claiming
        operatorFeeJuicePortalManager = await getFeeJuicePortalManager(operatorPXE);
        const {
            claim: operatorClaim,
            wallet: operatorWallet,
            account: operatorAccount
        } = await setupAccountWithFeeClaim(operatorPXE, operatorFeeJuicePortalManager);
        operator = operatorWallet;

        // deploy token contract and mint
        usdc = await deployTokenContractWithMinter(TOKEN_METADATA.usdc, minter);
        await usdc
            .withWallet(minter)
            .methods.mint_to_private(
                minter.getAddress(),
                user.getAddress(),
                MINT_AMOUNT
            )
            .send()
            .wait();

        // claim fee juice for user and deploy
        const claimAndPay = new FeeJuicePaymentMethodWithClaim(operator, operatorClaim);
        await operatorAccount.deploy({ fee: { paymentMethod: claimAndPay } }).wait();

        // register accounts and contracts in each PXE
        await userPXE.registerSender(user.getAddress());
        await operatorPXE.registerSender(minter.getAddress());
        await operatorPXE.registerSender(user.getAddress());
        await operatorPXE.registerContract(usdc);

    });

    test("check escrow key leaking", async () => {
        // deploy new escrow instance
        ({ contract: escrow, secretKey: escrowMasterKey } = await deployEscrowContract(
            userPXE,
            user,
            usdc.address,
            operator.getAddress(),
            INITIAL_SPEND_LIMIT
        ));

        // Check seller Escrow
        const sellerDefinition = await escrow
            .withWallet(user)
            .methods.get_config()
            .simulate();
        expect(sellerDefinition.owner).not.toEqual(0n);

        // register contract but do not register decryption keys
        // if contract is not registered they definitely can't call it
        await operatorPXE.registerContract(escrow);

        // check if maker note exists
        expect(async () => {
            await escrow
                .withWallet(operator)
                .methods.get_config()
                .simulate();
        }).toThrow()

        // add account to buyer pxe
        await operatorPXE.registerAccount(escrowMasterKey, await escrow.partialAddress);
        await escrow.withWallet(operator).methods.sync_private_state().simulate();
        const buyerDefinition = await escrow
            .withWallet(operator)
            .methods
            .get_config()
            .simulate();
        // expect(buyerDefinition.owner).toEqual(escrow.address.toBigInt());
        expect(buyerDefinition.owner).not.toEqual(0n);
    });

    test("e2e", async () => {
        
    });
});

// // deploy new escrow instance
//         ({ contract: escrow, secretKey: escrowMasterKey } = await deployEscrowContract(
//             userPXE,
//             seller,
//             usdc.address,
//             sellTokenAmount,
//             eth.address,
//             buyTokenAmount,
//         ));

//         // check balances before
//         usdc = usdc.withWallet(seller);
//         expect(expectBalancePrivate(usdc, seller.getAddress(), sellerUSDCInitialBalance)).toBeTruthy();
//         expect(expectBalancePrivate(usdc, escrow.address, 0n)).toBeTruthy();

//         // deposit tokens into the escrow
//         await depositToEscrow(
//             escrow,
//             seller,
//             usdc,
//             sellTokenAmount,
//         );

//         // check USDC balances after transfer in
//         usdc = usdc.withWallet(seller);
//         expect(
//             expectBalancePrivate(usdc, seller.getAddress(), sellerUSDCInitialBalance - sellTokenAmount)
//         ).toBeTruthy();
//         expect(expectBalancePrivate(usdc, escrow.address, sellTokenAmount)).toBeTruthy();


//         // check buyer balance balances before filling order
//         usdc = usdc.withWallet(buyer);
//         eth = eth.withWallet(buyer);
//         expect(expectBalancePrivate(eth, seller.getAddress(), buyerETHInitialBalance)).toBeTruthy();
//         expect(expectBalancePrivate(usdc, seller.getAddress(), 0n)).toBeTruthy();
//         expect(expectBalancePrivate(eth, escrow.address, 0n)).toBeTruthy();

//         // give buyer knowledge of the escrow
//         await operatorPXE.registerAccount(escrowMasterKey, await escrow.partialAddress);
//         await operatorPXE.registerContract(escrow);
//         await escrow.withWallet(buyer).methods.sync_private_state().simulate();

//         // transfer tokens back out
//         await fillOTCOrder(escrow, buyer, eth, buyTokenAmount);

//         // check balances after filling order
//         expect(
//             expectBalancePrivate(eth, buyer.getAddress(), buyerETHInitialBalance - buyTokenAmount)
//         ).toBeTruthy();
//         expect(expectBalancePrivate(usdc, buyer.getAddress(), sellTokenAmount)).toBeTruthy();
//         expect(expectBalancePrivate(eth, seller.getAddress(), buyTokenAmount)).toBeTruthy();
//         expect(expectBalancePrivate(usdc, escrow.address, 0n)).toBeTruthy();