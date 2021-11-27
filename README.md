# Solidity Contract
Here we store the latest changes in our solidity contract

We will have all the functions that owner can call and other don't and explain what they do so anyone can understand, not only developers.

    // in case we want to change the company that markets our coin
    function setMarketingWallet(address newWallet) external onlyOwner{
        marketingWallet = newWallet;
    }
    // will be used when we change our liquidity provider
    function setLiquidityWallet(address newWallet) external onlyOwner{
        liquidityWallet = newWallet;
    }
    // when the price will get bigger we might want to lower the threshold when the contracts makes the liquidity to save money.
    function setSwapTokensAtAmount(uint256 amount) external onlyOwner{
        swapTokensAtAmount = amount * 10**decimals();
    }
    // in the start will be set at 2% but in future in case we belive that even 2% is to risky we might lower it.
    function setMaxWalletBalance(uint256 amount) external onlyOwner{
        maxWalletBalance = amount * 10**decimals();
    }

    // This function is used to lower the amount need by the buyers to receive BUSD Rewards
    function setMinTokensToGetRewards(uint256 amount) external onlyOwner{
        dividendTracker.setMinimumBalanceForRewards(amount * 10**decimals());
    }
    // This function sets the maxium amount of tokens that can be sold in a transaction. we place a minim of 10M so we can't lower more then this (rug pull prevention)
    function setMaxTxAmount(uint256 amount) external onlyOwner{
        require(amount > 10_000 * 10**decimals(), "Amount must be > 10M");
        maxTxAmount = amount * 10**decimals();
    }   
    // once enabled it can't be disabled
    function enableSwap() external onlyOwner{
        swapEnabled = true;
    }
    // this is used in case we have investors that because of a slow bsc chain didn't receive the dividends that pay you the reward
    function updateDividendTracker(address newAddress) public onlyOwner {
        require(newAddress != address(dividendTracker), "HDR : The dividend tracker already has that address");

        HDRDividendTracker newDividendTracker = HDRDividendTracker(payable(newAddress));

        require(newDividendTracker.owner() == address(this), "HDR : The new dividend tracker must be owned by the HDR  token contract");

        newDividendTracker.excludeFromDividends(address(newDividendTracker), true);
        newDividendTracker.excludeFromDividends(address(this), true);
        newDividendTracker.excludeFromDividends(owner(), true);
        newDividendTracker.excludeFromDividends(address(router), true);

        emit UpdateDividendTracker(newAddress, address(dividendTracker));

        dividendTracker = newDividendTracker;
    }
    // this function is used to change the exchange in case in the future we want to move from pancake swap
    function updateRouter(address newAddress) public onlyOwner {
        require(newAddress != address(router), "HDR : The router already has that address");
        emit Updaterouter(newAddress, address(router));
        router = IRouter(newAddress);
    }
    // used when we have new marketing wallets or liquidity owners
    function excludeFromFees(address account, bool excluded) public onlyOwner {
        require(_isExcludedFromFees[account] != excluded, "HDR : Account is already the value of 'excluded'");
        _isExcludedFromFees[account] = excluded;

        emit ExcludeFromFees(account, excluded);
    }
    // used when we have new marketing wallets or liquidity owners
    function excludeMultipleAccountsFromFees(address[] calldata accounts, bool excluded) public onlyOwner {
        for(uint256 i = 0; i < accounts.length; i++) {
            _isExcludedFromFees[accounts[i]] = excluded;
        }

        emit ExcludeMultipleAccountsFromFees(accounts, excluded);
    }

    function setAutomatedMarketMakerPair(address newPair, bool value) public onlyOwner {
        _setAutomatedMarketMakerPair(newPair, value);
    }
    // used when we have new marketing wallets or liquidity owners
    function excludeFromDividends(address account, bool value) external onlyOwner{
        dividendTracker.excludeFromDividends(account, value);
    }
