// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {Test} from "forge-std/Test.sol";

import {UD60x18} from "@prb/math/UD60x18.sol";

import {IV3SwapRouter} from "@uniswap/swap-router-contracts/contracts/interfaces/IV3SwapRouter.sol";
import {IQuoterV2} from "@uniswap/v3-periphery/contracts/interfaces/IQuoterV2.sol";

import {ISolidStateERC20} from "@solidstate/contracts/token/ERC20/SolidStateERC20.sol";
import {IERC20} from "@solidstate/contracts/interfaces/IERC20.sol";

import {IDiamondWritableInternal} from "@solidstate/contracts/proxy/diamond/writable/IDiamondWritableInternal.sol";

import {ZERO, ONE} from "contracts/libraries/Constants.sol";
import {Permit2} from "contracts/libraries/Permit2.sol";
import {Position} from "contracts/libraries/Position.sol";
import {OptionMath} from "contracts/libraries/OptionMath.sol";

import {IPoolFactory} from "contracts/factory/IPoolFactory.sol";
import {PoolFactory} from "contracts/factory/PoolFactory.sol";
import {PoolFactoryProxy} from "contracts/factory/PoolFactoryProxy.sol";

import {IPoolMock} from "contracts/test/pool/IPoolMock.sol";
import {IPoolInternal} from "contracts/pool/IPoolInternal.sol";
import {PoolBase} from "contracts/pool/PoolBase.sol";
import {PoolCore} from "contracts/pool/PoolCore.sol";
import {PoolCoreMock} from "contracts/test/pool/PoolCoreMock.sol";
import {PoolTrade} from "contracts/pool/PoolTrade.sol";
import {PoolStorage} from "contracts/pool/PoolStorage.sol";

import {Premia} from "contracts/proxy/Premia.sol";

import {ERC20Router} from "contracts/router/ERC20Router.sol";

import {OracleAdapterMock} from "contracts/test/oracle/OracleAdapterMock.sol";

import {ExchangeHelper} from "contracts/ExchangeHelper.sol";

import {Assertions} from "./Assertions.sol";

contract DeployTest is Test, Assertions {
    uint256 mainnetFork;

    address base;
    address quote;
    OracleAdapterMock oracleAdapter;
    IPoolFactory.PoolKey poolKey;
    PoolFactory factory;
    Premia diamond;
    ERC20Router router;
    ExchangeHelper exchangeHelper;

    IPoolMock pool;

    IV3SwapRouter constant uniswapRouter =
        IV3SwapRouter(0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45);
    IQuoterV2 constant uniswapQuoter =
        IQuoterV2(0x61fFE014bA17989E743c5F6cB21bF9697530B21e);

    Position.Key posKey;

    IPoolInternal.TradeQuote tradeQuote;

    Users users;

    struct Users {
        address lp;
        address trader;
    }

    bytes4[] internal poolBaseSelectors;
    bytes4[] internal poolCoreMockSelectors;
    bytes4[] internal poolCoreSelectors;
    bytes4[] internal poolTradeSelectors;

    address public constant feeReceiver =
        address(0x000000000000000000000000000000000000dEaD);

    receive() external payable {}

    function setUp() public virtual {
        string memory ETH_RPC_URL = string.concat(
            "https://eth-mainnet.alchemyapi.io/v2/",
            vm.envString("API_KEY_ALCHEMY")
        );
        mainnetFork = vm.createFork(ETH_RPC_URL);
        vm.selectFork(mainnetFork);

        users = Users({lp: vm.addr(1), trader: vm.addr(2)});
        base = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2; // WETH
        quote = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48; // USDC

        oracleAdapter = new OracleAdapterMock(
            address(base),
            address(quote),
            UD60x18.wrap(1000 ether),
            UD60x18.wrap(1000 ether)
        );
        poolKey = IPoolFactory.PoolKey({
            base: base,
            quote: quote,
            oracleAdapter: address(oracleAdapter),
            strike: UD60x18.wrap(1000 ether),
            maturity: 1682668800,
            isCallPool: true
        });

        tradeQuote = IPoolInternal.TradeQuote({
            provider: users.lp,
            taker: address(0),
            price: UD60x18.wrap(0.1 ether),
            size: UD60x18.wrap(10 ether),
            isBuy: false,
            deadline: block.timestamp + 1 hours,
            salt: block.timestamp
        });

        diamond = new Premia();

        PoolFactory impl = new PoolFactory(
            address(diamond),
            address(oracleAdapter),
            address(base)
        );

        PoolFactoryProxy proxy = new PoolFactoryProxy(
            address(impl),
            UD60x18.wrap(0.1 ether),
            feeReceiver
        );

        factory = PoolFactory(address(proxy));

        router = new ERC20Router(address(factory));
        exchangeHelper = new ExchangeHelper();

        PoolBase poolBaseImpl = new PoolBase();

        PoolCoreMock poolCoreMockImpl = new PoolCoreMock(
            address(factory),
            address(router),
            address(exchangeHelper),
            address(base),
            feeReceiver
        );

        PoolCore poolCoreImpl = new PoolCore(
            address(factory),
            address(router),
            address(exchangeHelper),
            address(base),
            feeReceiver
        );

        PoolTrade poolTradeImpl = new PoolTrade(
            address(factory),
            address(router),
            address(exchangeHelper),
            address(base),
            feeReceiver
        );

        /////////////////////
        // Register facets //
        /////////////////////

        // PoolBase
        poolBaseSelectors.push(poolBaseImpl.accountsByToken.selector);
        poolBaseSelectors.push(poolBaseImpl.balanceOf.selector);
        poolBaseSelectors.push(poolBaseImpl.balanceOfBatch.selector);
        poolBaseSelectors.push(poolBaseImpl.isApprovedForAll.selector);
        poolBaseSelectors.push(poolBaseImpl.name.selector);
        poolBaseSelectors.push(poolBaseImpl.safeBatchTransferFrom.selector);
        poolBaseSelectors.push(poolBaseImpl.safeTransferFrom.selector);
        poolBaseSelectors.push(poolBaseImpl.setApprovalForAll.selector);
        poolBaseSelectors.push(poolBaseImpl.tokensByAccount.selector);
        poolBaseSelectors.push(poolBaseImpl.totalHolders.selector);
        poolBaseSelectors.push(poolBaseImpl.totalSupply.selector);

        // PoolCoreMock
        poolCoreMockSelectors.push(poolCoreMockImpl._getPricing.selector);
        poolCoreMockSelectors.push(poolCoreMockImpl._getStrandedArea.selector);
        poolCoreMockSelectors.push(poolCoreMockImpl._currentTick.selector);
        poolCoreMockSelectors.push(poolCoreMockImpl._liquidityRate.selector);
        poolCoreMockSelectors.push(poolCoreMockImpl._crossTick.selector);
        poolCoreMockSelectors.push(
            poolCoreMockImpl._getStrandedMarketPriceUpdateMock.selector
        );
        poolCoreMockSelectors.push(
            poolCoreMockImpl._isMarketPriceStrandedMock.selector
        );
        poolCoreMockSelectors.push(poolCoreMockImpl.formatTokenId.selector);
        poolCoreMockSelectors.push(poolCoreMockImpl.tradeQuoteHash.selector);
        poolCoreMockSelectors.push(poolCoreMockImpl.parseTokenId.selector);
        poolCoreMockSelectors.push(poolCoreMockImpl.protocolFees.selector);

        // PoolCore
        poolCoreSelectors.push(poolCoreImpl.annihilate.selector);
        poolCoreSelectors.push(poolCoreImpl.claim.selector);
        poolCoreSelectors.push(
            bytes4(
                keccak256(
                    "deposit((address,address,uint256,uint256,uint8),uint256,uint256,uint256,uint256,uint256,(address,uint256,uint256,uint256,bytes))"
                )
            )
        );
        poolCoreSelectors.push(
            bytes4(
                keccak256(
                    "deposit((address,address,uint256,uint256,uint8),uint256,uint256,uint256,uint256,uint256,(address,uint256,uint256,uint256,bytes),bool)"
                )
            )
        );
        poolCoreSelectors.push(poolCoreImpl.exercise.selector);
        poolCoreSelectors.push(poolCoreImpl.getClaimableFees.selector);
        poolCoreSelectors.push(poolCoreImpl.getNearestTicksBelow.selector);
        poolCoreSelectors.push(poolCoreImpl.getPoolSettings.selector);
        poolCoreSelectors.push(poolCoreImpl.marketPrice.selector);
        poolCoreSelectors.push(poolCoreImpl.settle.selector);
        poolCoreSelectors.push(poolCoreImpl.settlePosition.selector);
        poolCoreSelectors.push(poolCoreImpl.swapAndDeposit.selector);
        poolCoreSelectors.push(poolCoreImpl.takerFee.selector);
        poolCoreSelectors.push(poolCoreImpl.transferPosition.selector);
        poolCoreSelectors.push(poolCoreImpl.withdraw.selector);
        poolCoreSelectors.push(poolCoreImpl.withdrawAndSwap.selector);
        poolCoreSelectors.push(poolCoreImpl.writeFrom.selector);

        // PoolTrade
        poolTradeSelectors.push(poolTradeImpl.cancelTradeQuotes.selector);
        poolTradeSelectors.push(poolTradeImpl.fillQuote.selector);
        poolTradeSelectors.push(poolTradeImpl.fillQuoteAndSwap.selector);
        poolTradeSelectors.push(poolTradeImpl.swapAndFillQuote.selector);
        poolTradeSelectors.push(poolTradeImpl.getTradeQuote.selector);
        poolTradeSelectors.push(
            poolTradeImpl.getTradeQuoteFilledAmount.selector
        );
        poolTradeSelectors.push(poolTradeImpl.isTradeQuoteValid.selector);
        poolTradeSelectors.push(poolTradeImpl.swapAndTrade.selector);
        poolTradeSelectors.push(poolTradeImpl.trade.selector);
        poolTradeSelectors.push(poolTradeImpl.tradeAndSwap.selector);

        IDiamondWritableInternal.FacetCut[]
            memory facetCuts = new IDiamondWritableInternal.FacetCut[](4);

        facetCuts[0] = IDiamondWritableInternal.FacetCut(
            address(poolBaseImpl),
            IDiamondWritableInternal.FacetCutAction.ADD,
            poolBaseSelectors
        );

        facetCuts[1] = IDiamondWritableInternal.FacetCut(
            address(poolCoreMockImpl),
            IDiamondWritableInternal.FacetCutAction.ADD,
            poolCoreMockSelectors
        );

        facetCuts[2] = IDiamondWritableInternal.FacetCut(
            address(poolCoreImpl),
            IDiamondWritableInternal.FacetCutAction.ADD,
            poolCoreSelectors
        );

        facetCuts[3] = IDiamondWritableInternal.FacetCut(
            address(poolTradeImpl),
            IDiamondWritableInternal.FacetCutAction.ADD,
            poolTradeSelectors
        );

        diamond.diamondCut(facetCuts, address(0), "");

        ///////////////////////

        posKey = Position.Key({
            owner: users.lp,
            operator: users.lp,
            lower: UD60x18.wrap(0.1 ether),
            upper: UD60x18.wrap(0.3 ether),
            orderType: Position.OrderType.LC
        });
    }

    function deposit(
        uint256 depositSize
    ) internal returns (uint256 initialCollateral) {
        return deposit(UD60x18.wrap(depositSize));
    }

    function deposit(
        UD60x18 depositSize
    ) internal returns (uint256 initialCollateral) {
        bool isCall = poolKey.isCallPool;

        IERC20 token = IERC20(getPoolToken(isCall));
        initialCollateral = scaleDecimals(
            isCall ? depositSize : depositSize * poolKey.strike,
            isCall
        );

        vm.startPrank(users.lp);

        deal(address(token), users.lp, initialCollateral);
        token.approve(address(router), initialCollateral);

        (UD60x18 nearestBelowLower, UD60x18 nearestBelowUpper) = pool
            .getNearestTicksBelow(posKey.lower, posKey.upper);

        pool.deposit(
            posKey,
            nearestBelowLower,
            nearestBelowUpper,
            depositSize,
            ZERO,
            ONE,
            Permit2.emptyPermit()
        );

        vm.stopPrank();
    }

    function encodeSwapDataExactOutput(
        address tokenIn,
        address tokenOut,
        uint256 amountOut,
        uint256 amountInMaximum
    ) internal view returns (bytes memory) {
        return
            abi.encodePacked(
                bytes4(
                    keccak256(
                        "exactOutputSingle((address,address,uint24,address,uint256,uint256,uint160))"
                    )
                ),
                abi.encode(
                    tokenIn,
                    tokenOut,
                    3000,
                    address(exchangeHelper),
                    amountOut,
                    amountInMaximum,
                    0
                )
            );
    }

    function encodeSwapDataExactInput(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOutMinimum
    ) internal view returns (bytes memory) {
        return
            abi.encodePacked(
                bytes4(
                    keccak256(
                        "exactInputSingle((address,address,uint24,address,uint256,uint256,uint160))"
                    )
                ),
                abi.encode(
                    tokenIn,
                    tokenOut,
                    3000,
                    address(exchangeHelper),
                    amountIn,
                    amountOutMinimum,
                    0
                )
            );
    }

    function getSwapArgsExactOutput(
        address tokenIn,
        address tokenOut,
        uint256 amountInMax,
        uint256 amountOutMin,
        address refundAddress
    ) internal view returns (IPoolInternal.SwapArgs memory) {
        return
            getSwapArgs(
                tokenIn,
                tokenOut,
                amountInMax,
                amountOutMin,
                encodeSwapDataExactOutput(
                    tokenIn,
                    tokenOut,
                    amountOutMin,
                    amountInMax
                ),
                refundAddress
            );
    }

    function getSwapArgsExactInput(
        address tokenIn,
        address tokenOut,
        uint256 amountInMax,
        uint256 amountOutMin,
        address refundAddress
    ) internal view returns (IPoolInternal.SwapArgs memory) {
        return
            getSwapArgs(
                tokenIn,
                tokenOut,
                amountInMax,
                amountOutMin,
                encodeSwapDataExactInput(
                    tokenIn,
                    tokenOut,
                    amountInMax,
                    amountOutMin
                ),
                refundAddress
            );
    }

    function getSwapArgs(
        address tokenIn,
        address tokenOut,
        uint256 amountInMax,
        uint256 amountOutMin,
        bytes memory data,
        address refundAddress
    ) internal pure returns (IPoolInternal.SwapArgs memory) {
        return
            IPoolInternal.SwapArgs({
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                amountInMax: amountInMax,
                amountOutMin: amountOutMin,
                callee: address(uniswapRouter),
                allowanceTarget: address(uniswapRouter),
                data: data,
                refundAddress: refundAddress
            });
    }

    function getSwapQuoteExactOutput(
        address tokenIn,
        address tokenOut,
        uint256 amount
    ) internal returns (uint256) {
        (uint256 swapQuote, , , ) = IQuoterV2(uniswapQuoter)
            .quoteExactOutputSingle(
                IQuoterV2.QuoteExactOutputSingleParams({
                    tokenIn: tokenIn,
                    tokenOut: tokenOut,
                    amount: amount,
                    fee: 3000,
                    sqrtPriceLimitX96: 0
                })
            );

        return swapQuote;
    }

    function getSwapQuoteExactInput(
        address tokenIn,
        address tokenOut,
        uint256 amount
    ) internal returns (uint256) {
        (uint256 swapQuote, , , ) = IQuoterV2(uniswapQuoter)
            .quoteExactInputSingle(
                IQuoterV2.QuoteExactInputSingleParams({
                    tokenIn: tokenIn,
                    tokenOut: tokenOut,
                    amountIn: amount,
                    fee: 3000,
                    sqrtPriceLimitX96: 0
                })
            );

        return swapQuote;
    }

    function getPoolToken(bool isCall) internal view returns (address) {
        return isCall ? base : quote;
    }

    function getSwapToken(bool isCall) internal view returns (address) {
        return isCall ? quote : base;
    }

    function contractsToCollateral(
        UD60x18 amount,
        bool isCall
    ) internal view returns (UD60x18) {
        return isCall ? amount : amount * poolKey.strike;
    }

    function scaleDecimals(
        UD60x18 amount,
        bool isCall
    ) internal view returns (uint256) {
        uint8 decimals = ISolidStateERC20(getPoolToken(isCall)).decimals();
        return OptionMath.scaleDecimals(amount.unwrap(), 18, decimals);
    }

    function tokenId() internal view returns (uint256) {
        return
            PoolStorage.formatTokenId(
                posKey.operator,
                posKey.lower,
                posKey.upper,
                posKey.orderType
            );
    }
}
