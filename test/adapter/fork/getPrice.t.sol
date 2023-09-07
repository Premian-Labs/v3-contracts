// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {UD60x18, ud} from "@prb/math/UD60x18.sol";

import {IFeedRegistry} from "contracts/adapter/IFeedRegistry.sol";
import {IOracleAdapter} from "contracts/adapter/IOracleAdapter.sol";
import {IChainlinkAdapter} from "contracts/adapter/chainlink/IChainlinkAdapter.sol";
import {ERC20Mock} from "contracts/test/ERC20Mock.sol";
import {ChainlinkOraclePriceStub} from "contracts/test/adapter/ChainlinkOraclePriceStub.sol";

import {ChainlinkAdapter_PathCases_Shared_Test} from "../shared/pathCases.t.sol";

contract ChainlinkAdapter_GetPrice_Fork_Concrete_Test is ChainlinkAdapter_PathCases_Shared_Test {
    function isForkTest() internal virtual override returns (bool) {
        return true;
    }

    function test_getPrice_ReturnPriceForPair() public givenPaths {
        // Expected price values provided by DeFiLlama API (https://coins.llama.fi)
        uint80[39] memory expected = [
            1551253958184865268777, // WETH CHAINLINK_USD
            644639773341889, // CHAINLINK_USD WETH
            1552089999999999918145, // CHAINLINK_ETH CHAINLINK_USD
            999758000000000036, // DAI CHAINLINK_USD
            79200000000000002842, // AAVE CHAINLINK_USD
            45722646426775, // CHAINLINK_USD WBTC
            21871000000000000000000, // WBTC CHAINLINK_USD
            282273493583309, // BNT WETH
            6617057201666803, // AXS WETH
            1570958490531603047202, // WETH CRV
            12467891414141414, // CRV AAVE
            12623207070707071, // DAI AAVE
            79219171039391525824, // AAVE DAI
            987652555205930871, // CRV USDC
            20230716309186565, // USDC COMP
            45711581546340, // DAI WBTC
            21875331315600487869233, // WBTC USDC
            410573778449028981, // BOND AXS
            28582048972903472, // ALPHA BOND
            7725626669884812, // FXS WETH
            1202522448205321779824, // WETH MATIC
            97446588693957115, // USDC AXS
            120430653003309712, // ALPHA DAI
            8303533818524737597, // DAI ALPHA
            1168071047867190515, // FXS AXS
            93334502934327837, // ALPHA MATIC
            70927436248222092, // WETH WBTC
            1701565115821158997278, // WETH IMX
            587694229684187, // IMX WETH
            11254158609047422601, // AXS IMX
            2844972351326624072, // FXS BOND
            351497264827088818, // BOND FXS
            21871000000000000000000, // WBTC CHAINLINK_USD
            999177669148887615, // WBTC CHAINLINK_BTC
            14098916482760458280, // WBTC WETH
            70927436248222092, // WETH WBTC
            45711581546340, // DAI WBTC
            21875331315600487869233, // WBTC USDC
            49947716676413132518064 // WBTC BNT
        ];

        UD60x18 price = adapter.getPrice(p.tokenIn, p.tokenOut);

        assertApproxEqAbs(
            price.unwrap(),
            expected[caseId],
            (expected[caseId] * 3) / 100 // 3% tolerance
        );
    }

    function test_getPrice_Return1e18ForPairWithSameFeed() public {
        // tokenIn > tokenOut, tokenIn == 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE
        address testWETH = address(new ERC20Mock("testWETH", 18));

        IFeedRegistry.FeedMappingArgs[] memory feedMapping = new IFeedRegistry.FeedMappingArgs[](1);

        feedMapping[0] = IFeedRegistry.FeedMappingArgs(
            testWETH,
            CHAINLINK_USD,
            0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419 // Same feed as WETH/USD
        );

        adapter.batchRegisterFeedMappings(feedMapping);
        assertEq(adapter.getPrice(WETH, testWETH), ud(1e18));
        assertEq(adapter.getPrice(testWETH, WETH), ud(1e18));
    }

    function test_getPrice_ReturnPriceUsingCorrectDenomination() public {
        address tokenIn = WETH;
        address tokenOut = DAI;

        adapter.upsertPair(tokenIn, tokenOut);

        UD60x18 price = adapter.getPrice(tokenIn, tokenOut);
        UD60x18 invertedPrice = adapter.getPrice(tokenOut, tokenIn);

        assertEq(price, ud(1e18) / invertedPrice);

        //

        tokenIn = CRV;
        tokenOut = AAVE;

        adapter.upsertPair(tokenIn, tokenOut);

        price = adapter.getPrice(tokenIn, tokenOut);
        invertedPrice = adapter.getPrice(tokenOut, tokenIn);

        assertEq(price, ud(1e18) / invertedPrice);
    }

    function test_getPrice_ReturnCorrectPrice_IfPathExistsButNotCached() public {
        UD60x18 priceBeforeUpsert = adapter.getPrice(WETH, DAI);

        adapter.upsertPair(WETH, DAI);
        UD60x18 price = adapter.getPrice(WETH, DAI);

        assertEq(price, priceBeforeUpsert);
    }

    function test_getPrice_RevertIf_InvalidPrice() public {
        adapter.upsertPair(stubCoin, CHAINLINK_USD);

        int256[] memory prices = new int256[](1);
        uint256[] memory timestamps = new uint256[](1);

        prices[0] = 0;
        timestamps[0] = block.timestamp;

        stub.setup(ChainlinkOraclePriceStub.FailureMode.None, prices, timestamps);

        vm.expectRevert(abi.encodeWithSelector(IOracleAdapter.OracleAdapter__InvalidPrice.selector, prices[0]));
        adapter.getPrice(stubCoin, CHAINLINK_USD);
    }

    function test_getPrice_RevertIf_PriceLeftOfTargetStale() public {
        adapter.upsertPair(stubCoin, CHAINLINK_USD);

        int256[] memory prices = new int256[](1);
        uint256[] memory timestamps = new uint256[](1);

        prices[0] = 100000000000;
        timestamps[0] = block.timestamp - 25 hours;

        stub.setup(ChainlinkOraclePriceStub.FailureMode.None, prices, timestamps);

        assertEq(adapter.getPrice(stubCoin, CHAINLINK_USD), ud(uint256(prices[0]) * 1e10));
        vm.warp(block.timestamp + 1 seconds);

        vm.expectRevert(
            abi.encodeWithSelector(
                IChainlinkAdapter.ChainlinkAdapter__PriceLeftOfTargetStale.selector,
                timestamps[0],
                block.timestamp
            )
        );

        adapter.getPrice(stubCoin, CHAINLINK_USD);
    }

    function test_getPrice_RevertIf_PairNotSupported() public {
        vm.expectRevert(
            abi.encodeWithSelector(IOracleAdapter.OracleAdapter__PairNotSupported.selector, WETH, address(1))
        );
        adapter.getPrice(WETH, address(1));
    }

    function test_getPrice_RevertIf_TokensAreSame() public {
        vm.expectRevert(abi.encodeWithSelector(IOracleAdapter.OracleAdapter__TokensAreSame.selector, CRV, CRV));
        adapter.getPrice(CRV, CRV);
    }

    function test_getPrice_RevertIf_ZeroAddress() public {
        vm.expectRevert(IOracleAdapter.OracleAdapter__ZeroAddress.selector);
        adapter.getPrice(address(0), DAI);

        vm.expectRevert(IOracleAdapter.OracleAdapter__ZeroAddress.selector);
        adapter.getPrice(CRV, address(0));
    }

    function test_getPrice_CatchRevert() public {
        int256[] memory prices = new int256[](1);
        uint256[] memory timestamps = new uint256[](1);

        prices[0] = 100000000000;
        timestamps[0] = target - 90000;

        stub.setup(ChainlinkOraclePriceStub.FailureMode.LastRoundDataRevertWithReason, prices, timestamps);

        vm.expectRevert("reverted with reason");
        adapter.getPrice(stubCoin, CHAINLINK_USD);

        //

        stub.setup(ChainlinkOraclePriceStub.FailureMode.LastRoundDataRevert, prices, timestamps);

        vm.expectRevert(
            abi.encodeWithSelector(IChainlinkAdapter.ChainlinkAdapter__LatestRoundDataCallReverted.selector, "")
        );
        adapter.getPrice(stubCoin, CHAINLINK_USD);
    }
}
