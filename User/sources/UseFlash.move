module UseFlash::use_flash {
    use FlashLoan::flash_loan;

    public entry fun loan_and_repay(user: &signer, coin_addr: address, amount: u64) {
        // flash loan
        let (receipt, hot) = flash_loan::flashLoan(user, coin_addr, amount);

        // use loan

        // repay
        flash_loan::repay(user, receipt, hot);
    }
}