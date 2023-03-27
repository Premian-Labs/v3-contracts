// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {Test} from "forge-std/Test.sol";

import {UD60x18} from "@prb/math/src/UD60x18.sol";
import {Assertions} from "./Assertions.sol";

import {IDiamondWritableInternal} from "@solidstate/contracts/proxy/diamond/writable/IDiamondWritableInternal.sol";

import {Position} from "contracts/libraries/Position.sol";
import {OptionMath} from "contracts/libraries/OptionMath.sol";

import {ERC20Mock} from "contracts/test/ERC20Mock.sol";
import {OracleAdapterMock} from "contracts/test/oracle/OracleAdapterMock.sol";
import {IPoolFactory} from "contracts/factory/IPoolFactory.sol";
import {PoolFactory} from "contracts/factory/PoolFactory.sol";
import {PoolFactoryProxy} from "contracts/factory/PoolFactoryProxy.sol";
import {Premia} from "contracts/proxy/Premia.sol";
import {ERC20Router} from "contracts/router/ERC20Router.sol";
import {ExchangeHelper} from "contracts/ExchangeHelper.sol";

import {PoolBase} from "contracts/pool/PoolBase.sol";
import {PoolCore} from "contracts/pool/PoolCore.sol";
import {PoolTrade} from "contracts/pool/PoolTrade.sol";
import {PoolStorage} from "contracts/pool/PoolStorage.sol";

contract DeployTest is Test, Assertions {
    ERC20Mock base;
    ERC20Mock quote;
    OracleAdapterMock oracleAdapter;
    IPoolFactory.PoolKey poolKey;
    PoolFactory factory;
    Premia diamond;
    ERC20Router router;
    ExchangeHelper exchangeHelper;

    Position.Key posKey;

    Users users;

    struct Users {
        address lp;
        address trader;
    }

    bytes4[] internal poolBaseSelectors;
    bytes4[] internal poolCoreSelectors;
    bytes4[] internal poolTradeSelectors;

    address public constant feeReceiver =
        address(0x000000000000000000000000000000000000dEaD);

    receive() external payable {}

    function setUp() public virtual {
        vm.warp(1679758940);

        users = Users({lp: address(0x111), trader: address(0x222)});

        base = new ERC20Mock("WETH", 18);
        quote = new ERC20Mock("USDC", 6);
        oracleAdapter = new OracleAdapterMock(
            address(base),
            address(quote),
            UD60x18.wrap(1000 ether),
            UD60x18.wrap(1000 ether)
        );
        poolKey = IPoolFactory.PoolKey({
            base: address(base),
            quote: address(quote),
            oracleAdapter: address(oracleAdapter),
            strike: UD60x18.wrap(1000 ether),
            maturity: 1682668800,
            isCallPool: true
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

        // PoolCore
        poolCoreSelectors.push(poolCoreImpl.annihilate.selector);
        poolCoreSelectors.push(poolCoreImpl.claim.selector);
        poolCoreSelectors.push(
            bytes4(
                keccak256(
                    "deposit((address,address,uint256,uint256,uint8),uint256,uint256,uint256,uint256,uint256)"
                )
            )
        );
        poolCoreSelectors.push(
            bytes4(
                keccak256(
                    "deposit((address,address,uint256,uint256,uint8),uint256,uint256,uint256,uint256,uint256,bool)"
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
        poolCoreSelectors.push(poolCoreImpl.writeFrom.selector);

        // PoolTrade
        poolTradeSelectors.push(poolTradeImpl.cancelTradeQuotes.selector);
        poolTradeSelectors.push(poolTradeImpl.fillQuote.selector);
        poolTradeSelectors.push(poolTradeImpl.getTradeQuote.selector);
        poolTradeSelectors.push(
            poolTradeImpl.getTradeQuoteFilledAmount.selector
        );
        poolTradeSelectors.push(poolTradeImpl.isTradeQuoteValid.selector);
        poolTradeSelectors.push(poolTradeImpl.swapAndTrade.selector);
        poolTradeSelectors.push(poolTradeImpl.trade.selector);
        poolTradeSelectors.push(poolTradeImpl.tradeAndSwap.selector);

        IDiamondWritableInternal.FacetCut[]
            memory facetCuts = new IDiamondWritableInternal.FacetCut[](3);

        facetCuts[0] = IDiamondWritableInternal.FacetCut(
            address(poolBaseImpl),
            IDiamondWritableInternal.FacetCutAction.ADD,
            poolBaseSelectors
        );

        facetCuts[1] = IDiamondWritableInternal.FacetCut(
            address(poolCoreImpl),
            IDiamondWritableInternal.FacetCutAction.ADD,
            poolCoreSelectors
        );

        facetCuts[2] = IDiamondWritableInternal.FacetCut(
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

    function initialCollateral(
        bool isCall
    ) internal view returns (UD60x18 result) {
        result = UD60x18.wrap(1000 ether);
        if (!isCall) {
            result = result * poolKey.strike;
        }
    }

    function getPoolToken(bool isCall) internal view returns (address) {
        return isCall ? poolKey.base : poolKey.quote;
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
        uint8 decimals = ERC20Mock(getPoolToken(isCall)).decimals();
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
