// SPDX-License-Identifier: Unlicensed

pragma solidity ^0.8.10;

import "./DividendPayingToken.sol";
import "./SafeMath.sol";
import "./IterableMapping.sol";
import "./Ownable.sol";
import "./IDex.sol";


contract HDR  is ERC20, Ownable {
    using SafeMath for uint256;

    IRouter public router;
    address public  pair;

    string constant _name = "HDR Coin";
    string constant _symbol = "HDR";
    uint8 constant _decimals = 4;

    address constant public deadWallet = 0x000000000000000000000000000000000000dEaD;

    address public immutable BUSD = address(0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56); //BUSD

    bool private swapping;
    bool public swapEnabled = true;

    HDRDividendTracker public dividendTracker;

    uint256 public swapTokensAtAmount = 500_000_000 * (10**decimals());
    uint256 public maxWalletBalance = 2_000_000_000 * (10**decimals());  // 2% of total supply
    uint256 public maxTxAmount = 500_000_000 * (10 ** decimals());    // 0.5% of total supply
    uint256 public _totalSupply =  100_000_000_000 * (10 ** decimals());

    uint256 public  BUSDRewardsFee = 30;  // reward fee 3%
    uint256 public  marketingFee = 10; // marketing fee 1%
    uint256 public  liquidityFee = 5;  // liquidity 0.5%
    uint256 public  burnFee = 5;  // burn fee 0.5%
    uint256 public  totalFees = BUSDRewardsFee.add(marketingFee).add(liquidityFee);

    address public marketingWallet = 0x61a88541F1160FcC3Df744b7091eA046CBbb1e29;
    address public liquidityWallet = 0x04a2d5e9fD61c47f7407d68322E8Cad8a25C905f;

    // use by default 300,000 gas to process auto-claiming dividends
    uint256 public gasForProcessing = 300000;

    mapping (address => bool) private _isExcludedFromFees;

    // store addresses that a automatic market maker pairs. Any transfer *to* these addresses
    // could be subject to a maximum transfer amount
    mapping (address => bool) public automatedMarketMakerPairs;

    event UpdateDividendTracker(address indexed newAddress, address indexed oldAddress);

    event Updaterouter(address indexed newAddress, address indexed oldAddress);

    event ExcludeFromFees(address indexed account, bool isExcluded);

    event SetAutomatedMarketMakerPair(address indexed pair, bool indexed value);


    event GasForProcessingUpdated(uint256 indexed newValue, uint256 indexed oldValue);

    event SwapAndLiquify(
        uint256 tokensSwapped,
        uint256 ethReceived,
        uint256 tokensIntoLiqudity
    );

    event SwapETHForTokens(
        uint256 amountIn,
        address[] path
    );

    event SendDividends(
    	uint256 tokensSwapped,
    	uint256 amount
    );

    event ProcessedDividendTracker(
    	uint256 iterations,
    	uint256 claims,
        uint256 lastProcessedIndex,
    	bool indexed automatic,
    	uint256 gas,
    	address indexed processor
    );

     modifier lockTheSwap {
        swapping = true;
        _;
        swapping = false;
    }

    constructor()  ERC20(_name, _symbol) {

    	dividendTracker = new HDRDividendTracker();

    	IRouter _router = IRouter(0x10ED43C718714eb63d5aA57B78B54704E256024E);
         // Create a uniswap pair for this new token
        address _pair = IFactory(_router.factory())
            .createPair(address(this), _router.WETH());

        router = _router;
        pair = _pair;

        _setAutomatedMarketMakerPair(_pair, true);

        // exclude from receiving dividends
        dividendTracker.excludeFromDividends(address(dividendTracker), true);
        dividendTracker.excludeFromDividends(address(this), true);
        dividendTracker.excludeFromDividends(deadWallet, true);

        // exclude from paying fees or having max transaction amount
        excludeFromFees(owner(), true);
        excludeFromFees(address(this), true);
        excludeFromFees(marketingWallet, true);
        excludeFromFees(deadWallet, true);

        /*
            _mint is an internal function in ERC20.sol that is only called here,
            and CANNOT be called ever again
        */
        _mint(owner(), _totalSupply);
    }

    receive() external payable {

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

    // used when we have new marketing wallets or liquidity owners
    function excludeFromFees(address account, bool excluded) public onlyOwner {
        require(_isExcludedFromFees[account] != excluded, "HDR : Account is already the value of 'excluded'");
        _isExcludedFromFees[account] = excluded;

        emit ExcludeFromFees(account, excluded);
    }

    function setAutomatedMarketMakerPair(address newPair, bool value) public onlyOwner {
        _setAutomatedMarketMakerPair(newPair, value);
    }
    // used when we have new marketing wallets or liquidity owners
    function excludeFromDividends(address account, bool value) external onlyOwner{
        dividendTracker.excludeFromDividends(account, value);
    }

    function _setAutomatedMarketMakerPair(address newPair, bool value) private {
        require(automatedMarketMakerPairs[newPair] != value, "HDR : Automated market maker pair is already set to that value");
        automatedMarketMakerPairs[newPair] = value;

        if(value) {
            dividendTracker.excludeFromDividends(newPair, value);
        }

        emit SetAutomatedMarketMakerPair(newPair, value);
    }

    function getClaimWait() external view returns(uint256) {
        return dividendTracker.claimWait();
    }

    function getCirculatingSupply() public view returns (uint256) {
        return _totalSupply.sub(balanceOf(deadWallet));
    }

    function getTotalDividendsDistributed() external view returns (uint256) {
        return dividendTracker.totalDividendsDistributed();
    }

    function isExcludedFromFees(address account) public view returns(bool) {
        return _isExcludedFromFees[account];
    }

    function withdrawableDividendOf(address account) public view returns(uint256) {
    	return dividendTracker.withdrawableDividendOf(account);
  	}

	function dividendTokenBalanceOf(address account) public view returns (uint256) {
		return dividendTracker.balanceOf(account);
	}

    function getAccountDividendsInfo(address account)
        external view returns (
            address,
            int256,
            int256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256) {
        return dividendTracker.getAccount(account);
    }

	function getAccountDividendsInfoAtIndex(uint256 index)
        external view returns (
            address,
            int256,
            int256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256) {
    	return dividendTracker.getAccountAtIndex(index);
    }

	function processDividendTracker(uint256 gas) external {
		(uint256 iterations, uint256 claims, uint256 lastProcessedIndex) = dividendTracker.process(gas);
		emit ProcessedDividendTracker(iterations, claims, lastProcessedIndex, false, gas, msg.sender);
    }

    function claim() external {
		dividendTracker.processAccount(payable(msg.sender), false);
    }

    function getLastProcessedIndex() external view returns(uint256) {
    	return dividendTracker.getLastProcessedIndex();
    }

    function getNumberOfDividendTokenHolders() external view returns(uint256) {
        return dividendTracker.getNumberOfTokenHolders();
    }
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
        require(amount > 500_000_000, "the max wallet can't be lowered more then 500.000.000");
        maxWalletBalance = amount * 10**decimals();
    }

    // This function is used to lower the amount need by the buyers to receive BUSD Rewards
    function setMinTokensToGetRewards(uint256 amount) external onlyOwner{
        require(amount > 1_000_000, "The min wallet can't be lowered more then 1.000.000");
        require(amount < 1_000_000_000, "The min wallet can't be greater then 1.000.000.000");
        dividendTracker.setMinimumBalanceForRewards(amount * 10**decimals());
    }
    // This function sets the maxium amount of tokens that can be sold in a transaction. we place a minim of 10M so we can't lower more then this (rug pull prevention)
    function setMaxTxAmount(uint256 amount) external onlyOwner{
        require(amount > 10_000 * 10**decimals(), "Amount must be > 10M");
        maxTxAmount = amount * 10**decimals();
    }

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal override {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");

        if(!automatedMarketMakerPairs[to] && !_isExcludedFromFees[from] && !_isExcludedFromFees[to] && to != deadWallet){
            require(balanceOf(to).add(amount) <= maxWalletBalance, "Balance is exceeding maxWalletBalance");
        }

        if(!_isExcludedFromFees[from] && !_isExcludedFromFees[to]){
            require(amount <= maxTxAmount, "Amount is exceeding maxTxAmount");
        }

        if(amount == 0) {
            super._transfer(from, to, 0);
            return;
        }

        uint256 contractTokenBalance = balanceOf(address(this));
        if(swapEnabled && !swapping && !automatedMarketMakerPairs[from] && !_isExcludedFromFees[from] && !_isExcludedFromFees[to]) {

            bool canSwap = contractTokenBalance >= swapTokensAtAmount;

            if (canSwap) {
                swapAndLiquify(swapTokensAtAmount.mul(totalFees - BUSDRewardsFee).div(totalFees));

                if(BUSDRewardsFee > 0){
                    uint256 sellTokens = swapTokensAtAmount.mul(BUSDRewardsFee).div(totalFees);
                    swapAndSendDividends(sellTokens);
                }
            }

        }

        bool takeFee = !swapping;

        // if any account belongs to _isExcludedFromFee account then remove the fee
        if(_isExcludedFromFees[from] || _isExcludedFromFees[to]) {
            takeFee = false;
        }


        if(takeFee) {
            uint256 fees = amount * totalFees / 1000;
            uint256 burnAmt = amount * burnFee / 1000;

        	amount = amount.sub(fees).sub(burnAmt);
            super._transfer(from, address(this), fees);
            super._transfer(from, deadWallet, burnAmt);
        }
        super._transfer(from, to, amount);

        try dividendTracker.setBalance(payable(from), balanceOf(from)) {} catch {}
        try dividendTracker.setBalance(payable(to), balanceOf(to)) {} catch {}

        if(!swapping) {
	    	uint256 gas = gasForProcessing;

	    	try dividendTracker.process(gas) returns (uint256 iterations, uint256 claims, uint256 lastProcessedIndex) {
	    		emit ProcessedDividendTracker(iterations, claims, lastProcessedIndex, true, gas, msg.sender);
	    	}
	    	catch {

	    	}
        }
    }

    function swapAndLiquify(uint256 tokens) private lockTheSwap{
        // Split the contract balance into halves
        uint256 denominator = (liquidityFee + marketingFee) * 2;
        uint256 tokensToAddLiquidityWith = tokens * liquidityFee / denominator;
        uint256 toSwap = tokens - tokensToAddLiquidityWith;

        uint256 initialBalance = address(this).balance;

        swapTokensForEth(toSwap);

        uint256 deltaBalance = address(this).balance - initialBalance;
        uint256 unitBalance= deltaBalance / (denominator - liquidityFee);
        uint256 BNBToAddLiquidityWith = unitBalance * liquidityFee;

        if(BNBToAddLiquidityWith > 0){
            // Add liquidity to pancake
            addLiquidity(tokensToAddLiquidityWith, BNBToAddLiquidityWith);
        }

        // Send BNB to marketing
        uint256 marketingAmt = unitBalance * 2 * marketingFee;
        if(marketingAmt > 0) payable(marketingWallet).transfer(marketingAmt);
    }

    function swapETHForTokens(uint256 amount) private {
        // generate the uniswap pair path of token -> weth
        address[] memory path = new address[](2);
        path[0] = router.WETH();
        path[1] = address(this);

      // make the swap
        router.swapExactETHForTokensSupportingFeeOnTransferTokens{value: amount}(
            0, // accept any amount of Tokens
            path,
            deadWallet, // Burn address
            block.timestamp.add(300)
        );

        emit SwapETHForTokens(amount, path);
    }

    function addLiquidity(uint256 tokenAmount, uint256 ethAmount) private {

        // approve token transfer to cover all possible scenarios
        _approve(address(this), address(router), tokenAmount);

        // add the liquidity
        router.addLiquidityETH{value: ethAmount}(
            address(this),
            tokenAmount,
            0, // slippage is unavoidable
            0, // slippage is unavoidable
            liquidityWallet,
            block.timestamp
        );

    }

    function swapTokensForEth(uint256 tokenAmount) private {

        // generate the uniswap pair path of token -> weth
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = router.WETH();

        _approve(address(this), address(router), tokenAmount);

        // make the swap
        router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0, // accept any amount of ETH
            path,
            address(this),
            block.timestamp
        );

    }
    function swapTokensForBUSD(uint256 tokenAmount) private {

        address[] memory path = new address[](3);
        path[0] = address(this);
        path[1] = router.WETH();
        path[2] = BUSD;

        _approve(address(this), address(router), tokenAmount);

        // make the swap
        router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            tokenAmount,
            0,
            path,
            address(this),
            block.timestamp
        );
    }

    function swapAndSendDividends(uint256 tokens) private lockTheSwap{
        swapTokensForBUSD(tokens);
        uint256 dividends = IERC20(BUSD).balanceOf(address(this));
        bool success = IERC20(BUSD).transfer(address(dividendTracker), dividends);

        if (success) {
            dividendTracker.distributeBUSDDividends(dividends);
            emit SendDividends(tokens, dividends);
        }
    }
}

contract HDRDividendTracker is Ownable, DividendPayingToken {
    using SafeMath for uint256;
    using SafeMathInt for int256;
    using IterableMapping for IterableMapping.Map;

    IterableMapping.Map private tokenHoldersMap;
    uint256 public lastProcessedIndex;

    mapping (address => bool) public excludedFromDividends;

    mapping (address => uint256) public lastClaimTimes;

    uint256 public claimWait;
    uint256 public minimumTokenBalanceForDividends;

    event ExcludeFromDividends(address indexed account);
    event ClaimWaitUpdated(uint256 indexed newValue, uint256 indexed oldValue);

    event Claim(address indexed account, uint256 amount, bool indexed automatic);

    constructor()  DividendPayingToken("HDR_Dividend_Tracker", "HDR_Dividend_Tracker") {
    	claimWait = 3600;
        minimumTokenBalanceForDividends = 500e6 * (10**9); //must hold 500_000_000 tokens
    }

    function _transfer(address, address, uint256) internal pure override{
        require(false, "HDR_Dividend_Tracker: No transfers allowed");
    }

    function withdrawDividend() public pure override {
        require(false, "HDR_Dividend_Tracker: withdrawDividend disabled. Use the 'claim' function on the main HDR contract.");
    }
    // this function might be used if we change the marketing wallet, to exclude him from taking profits for the coins inside the wallet.
    function excludeFromDividends(address account, bool value) external onlyOwner {
    	require(excludedFromDividends[account] != value);
    	excludedFromDividends[account] = value;
      if(value == true){
        _setBalance(account, 0);
        tokenHoldersMap.remove(account);
      }
      else{
        _setBalance(account, balanceOf(account));
        tokenHoldersMap.set(account, balanceOf(account));
      }
    }
    // this function changes the time you have to wait until you can claim, must be between 1 and 24h
    function updateClaimWait(uint256 newClaimWait) external onlyOwner {
        require(newClaimWait >= 3600 && newClaimWait <= 86400, "HDR_Dividend_Tracker: claimWait must be updated to between 1 and 24 hours");
        require(newClaimWait != claimWait, "HDR_Dividend_Tracker: Cannot update claimWait to same value");
        emit ClaimWaitUpdated(newClaimWait, claimWait);
        claimWait = newClaimWait;
    }
    // This function is used to lower the amount need by the buyers to receive BUSD Rewards
    function setMinimumBalanceForRewards(uint256 amount) external onlyOwner{
        require(amount > 1_000_000, "The min wallet can't be lowered more then 1.000.000");
        require(amount < 1_000_000_000, "The min wallet can't be greater then 1.000.000.000");
        minimumTokenBalanceForDividends = amount;
    }

    function getLastProcessedIndex() external view returns(uint256) {
    	return lastProcessedIndex;
    }

    function getNumberOfTokenHolders() external view returns(uint256) {
        return tokenHoldersMap.keys.length;
    }

    function getAccount(address _account)
        public view returns (
            address account,
            int256 index,
            int256 iterationsUntilProcessed,
            uint256 withdrawableDividends,
            uint256 totalDividends,
            uint256 lastClaimTime,
            uint256 nextClaimTime,
            uint256 secondsUntilAutoClaimAvailable) {
        account = _account;

        index = tokenHoldersMap.getIndexOfKey(account);

        iterationsUntilProcessed = -1;

        if(index >= 0) {
            if(uint256(index) > lastProcessedIndex) {
                iterationsUntilProcessed = index.sub(int256(lastProcessedIndex));
            }
            else {
                uint256 processesUntilEndOfArray = tokenHoldersMap.keys.length > lastProcessedIndex ?
                                                        tokenHoldersMap.keys.length.sub(lastProcessedIndex) :
                                                        0;


                iterationsUntilProcessed = index.add(int256(processesUntilEndOfArray));
            }
        }


        withdrawableDividends = withdrawableDividendOf(account);
        totalDividends = accumulativeDividendOf(account);

        lastClaimTime = lastClaimTimes[account];

        nextClaimTime = lastClaimTime > 0 ?
                                    lastClaimTime.add(claimWait) :
                                    0;

        secondsUntilAutoClaimAvailable = nextClaimTime > block.timestamp ?
                                                    nextClaimTime.sub(block.timestamp) :
                                                    0;
    }


    function getAccountAtIndex(uint256 index)
        public view returns (
            address,
            int256,
            int256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256) {
    	if(index >= tokenHoldersMap.size()) {
            return (0x0000000000000000000000000000000000000000, -1, -1, 0, 0, 0, 0, 0);
        }

        address account = tokenHoldersMap.getKeyAtIndex(index);

        return getAccount(account);
    }

    function canAutoClaim(uint256 lastClaimTime) private view returns (bool) {
    	if(lastClaimTime > block.timestamp)  {
    		return false;
    	}

    	return block.timestamp.sub(lastClaimTime) >= claimWait;
    }

    function setBalance(address payable account, uint256 newBalance) external onlyOwner {
    	if(excludedFromDividends[account]) {
    		return;
    	}

    	if(newBalance >= minimumTokenBalanceForDividends) {
            _setBalance(account, newBalance);
    		tokenHoldersMap.set(account, newBalance);
    	}
    	else {
            _setBalance(account, 0);
    		tokenHoldersMap.remove(account);
    	}

    	processAccount(account, true);
    }

    function process(uint256 gas) public returns (uint256, uint256, uint256) {
    	uint256 numberOfTokenHolders = tokenHoldersMap.keys.length;

    	if(numberOfTokenHolders == 0) {
    		return (0, 0, lastProcessedIndex);
    	}

    	uint256 _lastProcessedIndex = lastProcessedIndex;

    	uint256 gasUsed = 0;

    	uint256 gasLeft = gasleft();

    	uint256 iterations = 0;
    	uint256 claims = 0;

    	while(gasUsed < gas && iterations < numberOfTokenHolders) {
    		_lastProcessedIndex++;

    		if(_lastProcessedIndex >= tokenHoldersMap.keys.length) {
    			_lastProcessedIndex = 0;
    		}

    		address account = tokenHoldersMap.keys[_lastProcessedIndex];

    		if(canAutoClaim(lastClaimTimes[account])) {
    			if(processAccount(payable(account), true)) {
    				claims++;
    			}
    		}

    		iterations++;

    		uint256 newGasLeft = gasleft();

    		if(gasLeft > newGasLeft) {
    			gasUsed = gasUsed.add(gasLeft.sub(newGasLeft));
    		}

    		gasLeft = newGasLeft;
    	}

    	lastProcessedIndex = _lastProcessedIndex;

    	return (iterations, claims, lastProcessedIndex);
    }

    function processAccount(address payable account, bool automatic) public onlyOwner returns (bool) {
        uint256 amount = _withdrawDividendOfUser(account);

    	if(amount > 0) {
    		lastClaimTimes[account] = block.timestamp;
            emit Claim(account, amount, automatic);
    		return true;
    	}

    	return false;
    }
}
