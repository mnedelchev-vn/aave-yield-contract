// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.0;
pragma abicoder v2;

import './Ownable.sol';

contract YieldContract is Ownable {
    address WETH_address;
    IWETH WETH;

    address USDC_address;
    IUSDC USDC;

    address SwapRouter_address;
    ISwapRouter SwapRouter;

    address Aave_address;
    IAave Aave;

    IQuoter Quoter;

    uint8 public WITHDRAW_FEE = 2;
    uint16 public UNISWAP_SLIPPAGE = 20;
    uint24 public UNISWAP_FEE = 3000;
    uint160 public UNISWAP_SQRT_PRICE_LIMIT_x96 = 0;
    bool public DEPOSITS_STOPPED = false;
    uint256 public MIN_DEPOSIT = 10000000000000;
    mapping(address => uint256) public depositors;

    /**
     * Sets maximum allowance of `Aave_address` over the contract USDC tokens.
     * Sets maximum allowance of `SwapRouter_address` over the contract USDC tokens.
     */
    constructor(address _WETH_address, address _USDC_address, address _SwapRouter_address, address _Aave_address, address _Quoter_address) {
        USDC.approve(Aave_address, 115792089237316195423570985008687907853269984665640564039457584007913129639935);
        USDC.approve(SwapRouter_address, 115792089237316195423570985008687907853269984665640564039457584007913129639935);

        WETH_address = _WETH_address;
        WETH = IWETH(_WETH_address);

        USDC_address = _USDC_address;
        USDC = IUSDC(_USDC_address);

        SwapRouter_address = _SwapRouter_address;
        SwapRouter = ISwapRouter(_SwapRouter_address);

        Aave_address = _Aave_address;
        Aave = IAave(_Aave_address);

        Quoter = IQuoter(_Quoter_address);
    }

    // ==================================== EVENTS ====================================
    event BoughtAndDeposited(address indexed _depositor, uint256 _tokenIn, uint256 _tokenOut);

    event Withdraw(address indexed _depositor, uint256 _tokenIn, uint256 _tokenOut);
    // ==================================== /EVENTS ====================================

    // ==================================== MODIFIERS ====================================
    modifier ifDepositsStopped() {
        require(!DEPOSITS_STOPPED, "ERROR: deposits are stopped.");
        _;
    }
    // ==================================== /MODIFIERS ====================================

    // ==================================== CONTRACT ADMIN ====================================
    /**
     * Serve as contract circuit breaker.
     */
    function stopUnstopDeposits() external onlyOwner {
        if (!DEPOSITS_STOPPED) {
            DEPOSITS_STOPPED = true;
        } else {
            DEPOSITS_STOPPED = false;
        }
    }

    function editApprovals(uint256 _aave_approval, uint256 _uniswap_approval) external onlyOwner {
        USDC.approve(Aave_address, _aave_approval);
        USDC.approve(SwapRouter_address, _uniswap_approval);
    }

    function setContractParams(uint8 _WITHDRAW_FEE, uint24 _UNISWAP_FEE, uint160 _UNISWAP_SQRT_PRICE_LIMIT_x96, uint256 _MIN_DEPOSIT) external onlyOwner {
        WITHDRAW_FEE = _WITHDRAW_FEE;
        UNISWAP_FEE = _UNISWAP_FEE;
        UNISWAP_SQRT_PRICE_LIMIT_x96 = _UNISWAP_SQRT_PRICE_LIMIT_x96;
        MIN_DEPOSIT = _MIN_DEPOSIT;
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
     * - `msg.value` has to be equal or greater than `MIN_DEPOSIT`.
     * - `msg.sender` cannot be the zero address.
     */
    function buyAndDeposit() external payable ifDepositsStopped {
        require(msg.value >= MIN_DEPOSIT, "ERROR: Not enough ETH deposit.");

        // calculate Uniswap amountOutMinimum to prevent sandwich attack
        uint256 quoteAmountOut = Quoter.quoteExactInputSingle(WETH_address, USDC_address, UNISWAP_FEE, msg.value, 0);
        require(quoteAmountOut > 0, "ERROR: failed predicting uniswap trade outcome.");
        uint256 amountOutMinimum = (quoteAmountOut * (100 - UNISWAP_SLIPPAGE)) / 100;

        // Uniswap purchase
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({tokenIn : WETH_address, tokenOut : USDC_address, fee : UNISWAP_FEE, recipient : address(this), amountIn : msg.value, amountOutMinimum : amountOutMinimum, sqrtPriceLimitX96 : UNISWAP_SQRT_PRICE_LIMIT_x96});
        uint256 amountOut = SwapRouter.exactInputSingle{value : msg.value}(params);

        // Aave USDC deposit
        Aave.supply(USDC_address, amountOut, address(this), 0);

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
    function _withdraw(uint256 _amount, address _address) internal {
        require(_amount <= depositors[_address] && _amount != 0, "ERROR: Invalid amount.");

        depositors[_address] -= _amount;

        // Aave USDC withdraw
        uint256 withdrawnAmount = Aave.withdraw(USDC_address, _amount, address(this));
        require(withdrawnAmount == _amount, "ERROR: Aave withdraw failed.");

        // calculate Uniswap amountOutMinimum to prevent sandwich attack
        uint256 quoteAmountOut = Quoter.quoteExactInputSingle(USDC_address, WETH_address, UNISWAP_FEE, withdrawnAmount, 0);
        require(quoteAmountOut > 0, "ERROR: failed predicting uniswap trade outcome.");
        uint256 amountOutMinimum = (quoteAmountOut * (100 - UNISWAP_SLIPPAGE)) / 100;

        // Uniswap sale
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({tokenIn : USDC_address, tokenOut : WETH_address, fee : UNISWAP_FEE, recipient : address(this), amountIn : withdrawnAmount, amountOutMinimum : amountOutMinimum, sqrtPriceLimitX96 : UNISWAP_SQRT_PRICE_LIMIT_x96});
        uint256 amountOut = SwapRouter.exactInputSingle(params);
        
        // swap WETH for ETH
        WETH.withdraw(amountOut);

        // charge the user with withdraw fee and send it to the owner of the contract
        uint256 withdrawFee = (amountOut * WITHDRAW_FEE) / 100;
        if (0 < withdrawFee) {
            payable(owner()).transfer(withdrawFee);
        }

        // Send back to the user the ETH amount from the USDC sale on Uniswap MINUS the withdraw fee
        payable(_address).transfer(amountOut - withdrawFee);

        emit Withdraw(_address, _amount, amountOut);
    }

    /**
     * Returns the total amount of deposited USDC in Aave.
     */
    function getTotalCollateralBase() view public returns (uint256) {
        (uint256 totalCollateralBase) = Aave.getUserAccountData(address(this));
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