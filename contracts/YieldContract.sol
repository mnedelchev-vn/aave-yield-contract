// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.0;

import "./Ownable.sol";

contract YieldContract is Ownable {
    address public wethAddress;
    IWETH wethInstance;

    address public usdcAddress;
    IUSDC usdcInstance;

    address public swapRouterAddress;
    ISwapRouter swapRouter;

    address public aaveAddress;
    IAave aaveInstance;

    IQuoter quoterInstance;

    uint8 public withdrawFee = 2;
    uint16 public uniswapSlippage = 20;
    uint24 public uniswapFee = 3000;
    bool public depositsStopped = false;
    uint160 public uniswapPriceLimit = 0;
    uint256 public minDeposit = 10000000000000;
    mapping(address => uint256) public depositors;

    /**
     * Sets maximum allowance of `aaveAddress` over the contract USDC tokens.
     * Sets maximum allowance of `swapRouterAddress` over the contract USDC tokens.
     */
    constructor(address _wethAddress, address _usdcAddress, address _swapRouterAddress, address _aaveAddress, address _quoterAddress) {
        wethAddress = _wethAddress;
        wethInstance = IWETH(wethAddress);

        usdcAddress = _usdcAddress;
        usdcInstance = IUSDC(_usdcAddress);

        swapRouterAddress = _swapRouterAddress;
        swapRouter = ISwapRouter(_swapRouterAddress);

        aaveAddress = _aaveAddress;
        aaveInstance = IAave(_aaveAddress);

        quoterInstance = IQuoter(_quoterAddress);

        usdcInstance.approve(aaveAddress, 115792089237316195423570985008687907853269984665640564039457584007913129639935);
        usdcInstance.approve(swapRouterAddress, 115792089237316195423570985008687907853269984665640564039457584007913129639935);
    }

    // ==================================== EVENTS ====================================
    event BoughtAndDeposited(address indexed _depositor, uint256 _tokenIn, uint256 _tokenOut);

    event Withdraw(address indexed _depositor, uint256 _tokenIn, uint256 _tokenOut);
    // ==================================== /EVENTS ====================================

    // ==================================== MODIFIERS ====================================
    modifier ifDepositsStopped() {
        require(!depositsStopped, "ERROR: deposits are stopped.");
        _;
    }
    // ==================================== /MODIFIERS ====================================

    // ==================================== CONTRACT ADMIN ====================================
    /**
     * Serve as contract circuit breaker.
     */
    function stopUnstopDeposits() external onlyOwner {
        if (!depositsStopped) {
            depositsStopped = true;
        } else {
            depositsStopped = false;
        }
    }

    function editApprovals(
        uint256 _aaveApproval, 
        uint256 _uniswapApproval
    ) external onlyOwner {
        usdcInstance.approve(aaveAddress, _aaveApproval);
        usdcInstance.approve(swapRouterAddress, _uniswapApproval);
    }

    function setContractParams(
        uint8 _withdrawFee, 
        uint24 _uniswapFee, 
        uint160 _uniswapPriceLimit, 
        uint256 _minDeposit
    ) external onlyOwner {
        withdrawFee = _withdrawFee;
        uniswapFee = _uniswapFee;
        uniswapPriceLimit = _uniswapPriceLimit;
        minDeposit = _minDeposit;
    }
    // ==================================== /CONTRACT ADMIN ====================================

    // ===================================== CONTRACT BODY =====================================
    /**
     * Swapping the given ETH amount for USDC at Uniswap pair.
     *
     * Depositing the USDC amount to Aave.
     *
     * Requirements:
     *
     * - `msg.value` has to be equal or greater than `minDeposit`.
     * - `msg.sender` cannot be the zero address.
     */
    function buyAndDeposit() external payable ifDepositsStopped {
        require(msg.value >= minDeposit, "ERROR: INVALID_ETH_DEPOSIT");

        // calculate Uniswap amountOutMinimum to prevent sandwich attack
        uint256 quoteAmountOut = quoterInstance.quoteExactInputSingle(wethAddress, usdcAddress, uniswapFee, msg.value, 0);
        require(quoteAmountOut > 0, "ERROR: FAILED_quoteAmountOut");
        uint256 amountOutMinimum = (quoteAmountOut * (100 - uniswapSlippage)) / 100;

        // Uniswap purchase
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({tokenIn : wethAddress, tokenOut : usdcAddress, fee : uniswapFee, recipient : address(this), amountIn : msg.value, amountOutMinimum : amountOutMinimum, sqrtPriceLimitX96 : uniswapPriceLimit});
        uint256 amountOut = swapRouter.exactInputSingle{value : msg.value}(params);

        // Aave USDC deposit
        aaveInstance.supply(usdcAddress, amountOut, address(this), 0);

        depositors[msg.sender] += amountOut;

        emit BoughtAndDeposited(msg.sender, msg.value, amountOut);
    }

    /**
     * Withdraw all of the user USDC deposit stake.
     */
    function withdraw() external {
        _withdraw(depositors[msg.sender], msg.sender);
    }

    /**
     * Withdraw specific USDC amount of the user deposit stake.
     */
    function withdraw(uint256 _specificAmount) external {
        _withdraw(_specificAmount, msg.sender);
    }

    /**
     * Withdrawing USDC tokens from AAVE deposit.
     *
     * Swapping the withdrawn USDC tokens amount for WETH at Uniswap WETH <=> USDC pair.
     *
     * Swapping WETH for ETH.
     *
     * Requirements:
     *
     * - `_amount` cannot be zero and has to be equal or smaller to user deposit stake.
     */
    function _withdraw(
        uint256 _amount, 
        address _address
    ) internal {
        require(_amount <= depositors[_address] && _amount != 0, "ERROR: INVALID_AMOUNT");

        depositors[_address] -= _amount;

        // Aave USDC withdraw
        uint256 withdrawnAmount = aaveInstance.withdraw(usdcAddress, _amount, address(this));
        require(withdrawnAmount == _amount, "ERROR: AAVE_FAILED");

        // calculate Uniswap amountOutMinimum to prevent sandwich attack
        uint256 quoteAmountOut = quoterInstance.quoteExactInputSingle(usdcAddress, wethAddress, uniswapFee, withdrawnAmount, 0);
        require(quoteAmountOut > 0, "ERROR: FAILED_quoteAmountOut");
        uint256 amountOutMinimum = (quoteAmountOut * (100 - uniswapSlippage)) / 100;

        // Uniswap sale
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({tokenIn : usdcAddress, tokenOut : wethAddress, fee : uniswapFee, recipient : address(this), amountIn : withdrawnAmount, amountOutMinimum : amountOutMinimum, sqrtPriceLimitX96 : uniswapPriceLimit});
        uint256 amountOut = swapRouter.exactInputSingle(params);
        
        // swap WETH for ETH
        wethInstance.withdraw(amountOut);

        // charge the user with withdraw fee and send it to the owner of the contract
        uint256 _withdrawFee = (amountOut * withdrawFee) / 100;
        if (0 < _withdrawFee) {
            payable(owner()).transfer(_withdrawFee);
        }

        // Send back to the user the ETH amount from the USDC sale on Uniswap MINUS the withdraw fee
        payable(_address).transfer(amountOut - withdrawFee);

        emit Withdraw(_address, _amount, amountOut);
    }

    /**
     * Returns the total amount of deposited USDC in Aave.
     */
    function getTotalCollateralBase() view public returns (uint256) {
        (uint256 totalCollateralBase) = aaveInstance.getUserAccountData(address(this));
        return totalCollateralBase;
    }

    /**
     * In order to make the WETH => ETH swap to work.
     */
    receive() external payable {}
    // ===================================== /CONTRACT BODY =====================================
}

interface IWETH {
    function withdraw(uint wad) external;
}

interface IUSDC {
    function approve(address spender, uint256 amount) external returns (bool);
}

interface ISwapRouter {
    function exactInputSingle(ExactInputSingleParams calldata params) external payable returns (uint256 amountOut);

    function getAmountsOut(uint amountIn, address[] calldata path) external view returns (uint[] memory amounts);

    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }
}

interface IQuoter {
    function quoteExactInputSingle(
        address tokenIn,
        address tokenOut,
        uint24 fee,
        uint256 amountIn,
        uint160 sqrtPriceLimitX96
    ) external returns (uint256 amountOut);
}

interface IAave {
    function supply(address asset, uint256 amount, address onBehalfOf, uint16 referralCode) external;

    function withdraw(address asset, uint256 amount, address to) external returns (uint256);

    function getUserAccountData(address user) external view returns (uint256 totalCollateralBase);
}

// MN bby ¯\_(ツ)_/¯