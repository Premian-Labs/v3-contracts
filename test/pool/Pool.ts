import { expect } from 'chai';
import { ethers } from 'hardhat';
import { ERC20Mock__factory, IPoolMock__factory } from '../../typechain';
import { BigNumber } from 'ethers';
import { parseEther, parseUnits } from 'ethers/lib/utils';
import { PoolUtil } from '../../utils/PoolUtil';
import { deployMockContract } from '@ethereum-waffle/mock-contract';
import {
  getValidMaturity,
  increaseTo,
  latest,
  ONE_HOUR,
} from '../../utils/time';
import { calculateQuoteHash, signQuote } from '../../utils/sdk/quote';
import { average, bnToNumber } from '../../utils/sdk/math';
import { OrderType, TokenType } from '../../utils/sdk/types';
import { ONE_ETHER, THREE_ETHER } from '../../utils/constants';

import { tokens } from '../../utils/addresses';
import { loadFixture } from '@nomicfoundation/hardhat-network-helpers';
import { formatTokenId, parseTokenId } from '../../utils/sdk/token';

const depositFnSig =
  'deposit((address,address,uint256,uint256,uint8,bool,uint256),uint256,uint256,uint256,uint256,uint256)';

type TestDefinition = {
  name: string;
  test: (isCallPool: boolean) => Promise<void>;
};

function runCallAndPutTests(tests: Array<TestDefinition>) {
  describe('call', () => {
    tests.forEach((el) => {
      it(el.name, () => el.test(true));
    });
  });

  describe('put', () => {
    tests.forEach((el) => {
      it(el.name, () => el.test(false));
    });
  });
}

describe('Pool', () => {
  const strike = parseEther('1000');
  const protocolFeePercentage = 0.5;
  const isCall = true;

  async function _deploy(isCall: boolean) {
    const [deployer, lp, trader, feeReceiver] = await ethers.getSigners();

    const base = await new ERC20Mock__factory(deployer).deploy('WETH', 18);
    const quote = await new ERC20Mock__factory(deployer).deploy('USDC', 6);

    const oracleAdapter = await deployMockContract(deployer as any, [
      'function quote(address,address) external view returns (uint256)',
    ]);

    await oracleAdapter.mock.quote.returns(parseUnits('1000', 18));

    const p = await PoolUtil.deploy(
      deployer,
      tokens.WETH.address,
      oracleAdapter.address,
      feeReceiver.address,
      parseEther('0.1'), // 10%
      true,
      true,
    );

    const maturity = await getValidMaturity(10, 'months');

    const deployPool = async (isCallPool: boolean) => {
      const tx = await p.poolFactory.deployPool(
        {
          base: base.address,
          quote: quote.address,
          oracleAdapter: oracleAdapter.address,
          strike,
          maturity,
          isCallPool,
        },
        {
          value: parseEther('1'),
        },
      );

      const r = await tx.wait(1);
      const poolAddress = (r as any).events[0].args.poolAddress;

      return IPoolMock__factory.connect(poolAddress, deployer);
    };

    const pool = await deployPool(isCall);

    const getTradeQuote = async () => {
      const timestamp = BigNumber.from(await latest());
      return {
        provider: lp.address,
        taker: ethers.constants.AddressZero,
        price: parseEther('0.1'),
        size: parseEther('10'),
        isBuy: false,
        deadline: timestamp.add(ONE_HOUR),
        salt: timestamp,
      };
    };

    const pKey = {
      owner: lp.address,
      operator: lp.address,
      lower: parseEther('0.1'),
      upper: parseEther('0.3'),
      orderType: OrderType.LC,
      isCall: isCall,
      strike: strike,
    } as const;
    Object.freeze(pKey);

    return {
      deployer,
      lp,
      trader,
      feeReceiver,
      pool,
      ...p,
      base,
      quote,
      oracleAdapter,
      maturity,
      pKey,
      getTradeQuote,
    };
  }

  async function deploy_CALL() {
    return _deploy(true);
  }

  async function deploy_PUT() {
    return _deploy(false);
  }

  async function _deployAndMintForLP(isCall: boolean) {
    const f = await _deploy(isCall);

    const initialCollateral = parseEther('1000');

    const token = isCall ? f.base : f.quote;

    await token.mint(f.lp.address, initialCollateral);
    await token.connect(f.lp).approve(f.router.address, initialCollateral);

    return { ...f, initialCollateral };
  }

  async function deployAndMintForLP_CALL() {
    return _deployAndMintForLP(true);
  }

  async function deployAndMintForLP_PUT() {
    return _deployAndMintForLP(false);
  }

  async function _deployAndMintForTraderAndLP(isCall: boolean) {
    const f = await _deploy(isCall);

    const initialCollateral = parseEther('10');

    const token = isCall ? f.base : f.quote;

    for (const user of [f.lp, f.trader]) {
      await token.mint(user.address, initialCollateral);
      await token.connect(user).approve(f.router.address, initialCollateral);
    }

    return { ...f, initialCollateral };
  }

  async function deployAndMintForTraderAndLP_CALL() {
    return _deployAndMintForTraderAndLP(true);
  }

  async function deployAndMintForTraderAndLP_PUT() {
    return _deployAndMintForTraderAndLP(false);
  }

  async function deposit(
    f: Awaited<ReturnType<typeof _deployAndMintForTraderAndLP>>,
    orderType: OrderType,
    depositSize: BigNumber,
  ) {
    const pKey = { ...f.pKey, orderType } as const;
    Object.freeze(pKey);

    const tokenId = await f.pool.formatTokenId(
      pKey.operator,
      pKey.lower,
      pKey.upper,
      pKey.orderType,
    );

    const nearestBelow = await f.pool.getNearestTicksBelow(
      pKey.lower,
      pKey.upper,
    );

    await f.pool
      .connect(f.lp)
      [depositFnSig](
        pKey,
        nearestBelow.nearestBelowLower,
        nearestBelow.nearestBelowUpper,
        depositSize,
        0,
        parseEther('1'),
      );

    return { ...f, tokenId, pKey, depositSize };
  }

  async function _deployAndDeposit_1000_CS(isCall: boolean) {
    return deposit(
      await _deployAndMintForLP(isCall),
      OrderType.CS,
      parseEther('1000'),
    );
  }

  async function deployAndDeposit_1000_CS_CALL() {
    return _deployAndDeposit_1000_CS(true);
  }

  async function deployAndDeposit_1000_CS_PUT() {
    return _deployAndDeposit_1000_CS(false);
  }

  async function _deployAndDeposit_1_CS(isCall: boolean) {
    return deposit(await _deployAndMintForLP(isCall), OrderType.CS, ONE_ETHER);
  }

  async function deployAndDeposit_1_CS_CALL() {
    return _deployAndDeposit_1_CS(true);
  }

  async function deployAndDeposit_1_CS_PUT() {
    return _deployAndDeposit_1_CS(false);
  }

  async function _deployAndDeposit_1000_LC(isCall: boolean) {
    return deposit(
      await _deployAndMintForLP(isCall),
      OrderType.LC,
      parseEther('1000'),
    );
  }

  async function deployAndDeposit_1000_LC_CALL() {
    return _deployAndDeposit_1000_LC(true);
  }

  async function deployAndDeposit_1000_LC_PUT() {
    return _deployAndDeposit_1000_LC(false);
  }

  async function _deployAndDeposit_1_LC(isCall: boolean) {
    return deposit(await _deployAndMintForLP(isCall), OrderType.LC, ONE_ETHER);
  }

  async function deployAndDeposit_1_LC_CALL() {
    return _deployAndDeposit_1_LC(true);
  }

  async function deployAndDeposit_1_LC_PUT() {
    return _deployAndDeposit_1_LC(false);
  }

  async function _deployAndBuy(isCall: boolean) {
    const f = await _deployAndDeposit_1_CS(isCall);

    const tradeSize = ONE_ETHER;
    const price = f.pKey.lower;
    const nextPrice = f.pKey.upper;
    const avgPrice = average(price, nextPrice);
    const takerFee = await f.pool.takerFee(
      tradeSize,
      tradeSize.mul(avgPrice).div(ONE_ETHER),
      true,
    );
    const totalPremium = await f.pool.getTradeQuote(tradeSize, true);

    const token = isCall ? f.base : f.quote;

    await token.mint(f.trader.address, totalPremium);
    await token.connect(f.trader).approve(f.router.address, totalPremium);

    await f.pool.connect(f.trader).trade(tradeSize, true, totalPremium);

    const protocolFees = await f.pool.protocolFees();

    return {
      ...f,
      tradeSize,
      price,
      nextPrice,
      avgPrice,
      takerFee,
      totalPremium,
      protocolFees,
    };
  }

  async function deployAndBuy_CALL() {
    return _deployAndBuy(true);
  }

  async function deployAndBuy_PUT() {
    return _deployAndBuy(false);
  }

  async function _deployAndSell(isCall: boolean) {
    const f = await _deployAndDeposit_1_LC(isCall);

    const tradeSize = ONE_ETHER;
    const price = f.pKey.upper;
    const nextPrice = f.pKey.lower;
    const avgPrice = average(price, nextPrice);
    const takerFee = await f.pool.takerFee(
      tradeSize,
      tradeSize.mul(avgPrice).div(ONE_ETHER),
      true,
    );

    const totalPremium = await f.pool.getTradeQuote(tradeSize, false);

    const token = isCall ? f.base : f.quote;

    await token.mint(f.trader.address, ONE_ETHER);
    await token.connect(f.trader).approve(f.router.address, ONE_ETHER);

    await f.pool.connect(f.trader).trade(tradeSize, false, totalPremium);

    const protocolFees = await f.pool.protocolFees();

    return {
      ...f,
      tradeSize,
      price,
      nextPrice,
      avgPrice,
      takerFee,
      totalPremium,
      protocolFees,
    };
  }

  async function deployAndSell_CALL() {
    return _deployAndSell(true);
  }

  async function deployAndSell_PUT() {
    return _deployAndSell(false);
  }

  describe('__internal', function () {
    describe('#_getPricing', () => {
      const tests: TestDefinition[] = [
        {
          name: 'should return pool state',
          test: shouldReturnPoolState,
        },
      ];

      runCallAndPutTests(tests);

      async function shouldReturnPoolState(isCallPool: boolean) {
        const { pool, lp, base, router } = await loadFixture(
          isCallPool ? deploy_CALL : deploy_PUT,
        );

        let isBuy = true;
        let args = await pool._getPricing(isBuy);

        expect(args.liquidityRate).to.eq(0);
        expect(args.marketPrice).to.eq(parseEther('0.001'));
        expect(args.lower).to.eq(parseEther('0.001'));
        expect(args.upper).to.eq(parseEther('1'));
        expect(args.isBuy).to.eq(isBuy);

        args = await pool._getPricing(!isBuy);

        expect(args.liquidityRate).to.eq(0);
        expect(args.marketPrice).to.eq(parseEther('0.001'));
        expect(args.lower).to.eq(parseEther('0.001'));
        expect(args.upper).to.eq(parseEther('1'));
        expect(args.isBuy).to.eq(!isBuy);

        let lower = parseEther('0.25');
        let upper = parseEther('0.75');

        let position = {
          lower: lower,
          upper: upper,
          operator: lp.address,
          owner: lp.address,
          orderType: OrderType.LC,
          isCall: isCall,
          strike: strike,
        };

        await base.connect(lp).approve(router.address, parseEther('2000'));

        const nearestBelow = await pool.getNearestTicksBelow(lower, upper);

        await base.mint(lp.address, parseEther('2000'));

        await pool
          .connect(lp)
          [depositFnSig](
            position,
            nearestBelow.nearestBelowLower,
            nearestBelow.nearestBelowUpper,
            parseEther('2000'),
            0,
            parseEther('1'),
          );

        args = await pool._getPricing(isBuy);

        expect(args.liquidityRate).to.eq(parseEther('4'));
        expect(args.marketPrice).to.eq(upper);
        expect(args.lower).to.eq(lower);
        expect(args.upper).to.eq(upper);
        expect(args.isBuy).to.eq(isBuy);

        args = await pool._getPricing(!isBuy);

        expect(args.liquidityRate).to.eq(parseEther('4'));
        expect(args.marketPrice).to.eq(upper);
        expect(args.lower).to.eq(lower);
        expect(args.upper).to.eq(upper);
        expect(args.isBuy).to.eq(!isBuy);
      }
    });

    describe('#_tradeQuoteHash', () => {
      const tests: TestDefinition[] = [
        {
          name: 'should successfully calculate a trade quote hash',
          test: shouldCalculateTradeQuoteHash,
        },
      ];

      runCallAndPutTests(tests);

      async function shouldCalculateTradeQuoteHash(isCallPool: boolean) {
        const { getTradeQuote, pool, lp } = await loadFixture(
          isCallPool ? deploy_CALL : deploy_PUT,
        );

        const quote = await getTradeQuote();
        expect(await pool.tradeQuoteHash(quote)).to.eq(
          await calculateQuoteHash(lp.provider!, quote, pool.address),
        );
      }
    });
  });

  describe('#getTradeQuote', () => {
    const tests: TestDefinition[] = [
      {
        name: 'should successfully return a buy trade quote',
        test: shouldReturnBuyTradeQuote,
      },
      {
        name: 'should successfully return a sell trade quote',
        test: shouldReturnSellTradeQuote,
      },
      {
        name: 'should revert if not enough liquidity to buy',
        test: shouldRevertIfNotEnoughBuyLiquidity,
      },
      {
        name: 'should revert if not enough liquidity to sell',
        test: shouldRevertIfNotEnoughSellLiquidity,
      },
    ];

    runCallAndPutTests(tests);

    async function shouldReturnBuyTradeQuote(isCallPool: boolean) {
      const { pool, pKey } = await loadFixture(
        isCallPool
          ? deployAndDeposit_1000_CS_CALL
          : deployAndDeposit_1000_CS_PUT,
      );

      const tradeSize = parseEther('500');
      const price = pKey.lower;
      const nextPrice = parseEther('0.2');
      const avgPrice = average(price, nextPrice);
      const takerFee = await pool.takerFee(
        tradeSize,
        tradeSize.mul(avgPrice).div(ONE_ETHER),
        true,
      );

      expect(await pool.getTradeQuote(tradeSize, true)).to.eq(
        tradeSize.mul(avgPrice).div(ONE_ETHER).add(takerFee),
      );
    }

    async function shouldReturnSellTradeQuote(isCallPool: boolean) {
      const { pool, pKey } = await loadFixture(
        isCallPool
          ? deployAndDeposit_1000_LC_CALL
          : deployAndDeposit_1000_LC_PUT,
      );

      const tradeSize = parseEther('500');
      const price = pKey.upper;
      const nextPrice = parseEther('0.2');
      const avgPrice = average(price, nextPrice);
      const takerFee = await pool.takerFee(
        tradeSize,
        tradeSize.mul(avgPrice).div(ONE_ETHER),
        true,
      );

      expect(await pool.getTradeQuote(tradeSize, false)).to.eq(
        tradeSize.mul(avgPrice).div(ONE_ETHER).sub(takerFee),
      );
    }

    async function shouldRevertIfNotEnoughBuyLiquidity(isCallPool: boolean) {
      const { pool, depositSize } = await loadFixture(
        isCallPool
          ? deployAndDeposit_1000_CS_CALL
          : deployAndDeposit_1000_CS_PUT,
      );

      await expect(
        pool.getTradeQuote(depositSize.add(1), true),
      ).to.be.revertedWithCustomError(pool, 'Pool__InsufficientLiquidity');
    }

    async function shouldRevertIfNotEnoughSellLiquidity(isCallPool: boolean) {
      const { pool, depositSize } = await loadFixture(
        isCallPool
          ? deployAndDeposit_1000_LC_CALL
          : deployAndDeposit_1000_LC_PUT,
      );

      await expect(
        pool.getTradeQuote(depositSize.add(1), false),
      ).to.be.revertedWithCustomError(pool, 'Pool__InsufficientLiquidity');
    }
  });

  describe('#deposit', () => {
    const fnSig = depositFnSig;

    describe(`#${fnSig}`, () => {
      const tests: TestDefinition[] = [
        {
          name: 'should revert if msg.sender != p.operator',
          test: shouldRevertIfSenderIsNotOperator,
        },
        {
          name: 'should revert if marketPrice is below minMarketPrice or above maxMarketPrice',
          test: shouldRevertIfMarketPriceIsOutOfSlippageRange,
        },
      ];

      runCallAndPutTests(tests);

      describe('OrderType LC', () => {
        it('should mint 1000 LP tokens and deposit 200 collateral (lower: 0.1 | upper 0.3 | size: 1000)', async () => {
          const { pool, lp, pKey, base, tokenId, depositSize } =
            await loadFixture(deployAndDeposit_1000_LC_CALL);

          const averagePrice = average(pKey.lower, pKey.upper);
          const collateralValue = depositSize.mul(averagePrice).div(ONE_ETHER);

          expect(await pool.balanceOf(lp.address, tokenId)).to.eq(depositSize);
          expect(await pool.totalSupply(tokenId)).to.eq(depositSize);
          expect(await base.balanceOf(pool.address)).to.eq(collateralValue);
          expect(await base.balanceOf(lp.address)).to.eq(
            depositSize.sub(collateralValue),
          );
          expect(await pool.marketPrice()).to.eq(pKey.upper);
        });
      });

      async function shouldRevertIfSenderIsNotOperator(isCallPool: boolean) {
        const { pool, deployer, pKey } = await loadFixture(
          isCallPool ? deploy_CALL : deploy_PUT,
        );

        await expect(
          pool
            .connect(deployer)
            [fnSig](pKey, 0, 0, THREE_ETHER, 0, parseEther('1')),
        ).to.be.revertedWithCustomError(pool, 'Pool__NotAuthorized');
      }

      async function shouldRevertIfMarketPriceIsOutOfSlippageRange(
        isCallPool: boolean,
      ) {
        const { pool, lp, pKey } = await loadFixture(
          isCallPool
            ? deployAndDeposit_1000_LC_CALL
            : deployAndDeposit_1000_LC_PUT,
        );

        expect(await pool.marketPrice()).to.eq(pKey.upper);

        await expect(
          pool.connect(lp)[fnSig](pKey, 0, 0, 0, pKey.upper.add(1), pKey.upper),
        ).to.be.revertedWithCustomError(pool, 'Pool__AboveMaxSlippage');

        await expect(
          pool
            .connect(lp)
            [fnSig](pKey, 0, 0, 0, pKey.upper.sub(10), pKey.upper.sub(1)),
        ).to.be.revertedWithCustomError(pool, 'Pool__AboveMaxSlippage');
      }

      it('should revert if zero size', async () => {
        const { pool, lp, pKey } = await loadFixture(deploy_CALL);

        await expect(
          pool.connect(lp)[fnSig](pKey, 0, 0, 0, 0, parseEther('1')),
        ).to.be.revertedWithCustomError(pool, 'Pool__ZeroSize');
      });

      it('should revert if option is expired', async () => {
        const { pool, lp, pKey, maturity } = await loadFixture(deploy_CALL);

        await increaseTo(maturity);
        await expect(
          pool.connect(lp)[fnSig](pKey, 0, 0, THREE_ETHER, 0, parseEther('1')),
        ).to.be.revertedWithCustomError(pool, 'Pool__OptionExpired');
      });

      it('should revert if range is not valid', async () => {
        const { pool, lp, pKey } = await loadFixture(deploy_CALL);

        await expect(
          pool
            .connect(lp)
            [fnSig](
              { ...pKey, lower: 0 },
              0,
              0,
              THREE_ETHER,
              0,
              parseEther('1'),
            ),
        ).to.be.revertedWithCustomError(pool, 'Pool__InvalidRange');

        await expect(
          pool
            .connect(lp)
            [fnSig](
              { ...pKey, upper: 0 },
              0,
              0,
              THREE_ETHER,
              0,
              parseEther('1'),
            ),
        ).to.be.revertedWithCustomError(pool, 'Pool__InvalidRange');

        await expect(
          pool
            .connect(lp)
            [fnSig](
              { ...pKey, lower: parseEther('0.5'), upper: parseEther('0.25') },
              0,
              0,
              THREE_ETHER,
              0,
              parseEther('1'),
            ),
        ).to.be.revertedWithCustomError(pool, 'Pool__InvalidRange');

        await expect(
          pool
            .connect(lp)
            [fnSig](
              { ...pKey, lower: parseEther('0.0001') },
              0,
              0,
              THREE_ETHER,
              0,
              parseEther('1'),
            ),
        ).to.be.revertedWithCustomError(pool, 'Pool__InvalidRange');

        await expect(
          pool
            .connect(lp)
            [fnSig](
              { ...pKey, upper: parseEther('1.01') },
              0,
              0,
              THREE_ETHER,
              0,
              parseEther('1'),
            ),
        ).to.be.revertedWithCustomError(pool, 'Pool__InvalidRange');
      });

      it('should revert if tick width is invalid', async () => {
        const { pool, lp, pKey } = await loadFixture(deploy_CALL);

        await expect(
          pool
            .connect(lp)
            [fnSig](
              { ...pKey, lower: parseEther('0.2501') },
              0,
              0,
              THREE_ETHER,
              0,
              parseEther('1'),
            ),
        ).to.be.revertedWithCustomError(pool, 'Pool__TickWidthInvalid');

        await expect(
          pool
            .connect(lp)
            [fnSig](
              { ...pKey, upper: parseEther('0.7501') },
              0,
              0,
              THREE_ETHER,
              0,
              parseEther('1'),
            ),
        ).to.be.revertedWithCustomError(pool, 'Pool__TickWidthInvalid');
      });
    });
  });

  describe('#withdraw', () => {
    describe('OrderType LC', () => {
      it('should burn 750 LP tokens and withdraw 150 collateral (lower: 0.1 | upper 0.3 | size: 750)', async () => {
        const {
          pool,
          lp,
          pKey,
          base,
          tokenId,
          depositSize,
          initialCollateral,
        } = await loadFixture(deployAndDeposit_1000_LC_CALL);

        const depositCollateralValue = parseEther('200');

        expect(await base.balanceOf(lp.address)).to.eq(
          initialCollateral.sub(depositCollateralValue),
        );
        expect(await base.balanceOf(pool.address)).to.eq(
          depositCollateralValue,
        );

        const withdrawSize = parseEther('750');

        const averagePrice = average(pKey.lower, pKey.upper);
        const withdrawCollateralValue = withdrawSize
          .mul(averagePrice)
          .div(ONE_ETHER);

        await pool.connect(lp).withdraw(pKey, withdrawSize, 0, parseEther('1'));
        expect(await pool.balanceOf(lp.address, tokenId)).to.eq(
          depositSize.sub(withdrawSize),
        );
        expect(await pool.totalSupply(tokenId)).to.eq(
          depositSize.sub(withdrawSize),
        );
        expect(await base.balanceOf(pool.address)).to.eq(
          depositCollateralValue.sub(withdrawCollateralValue),
        );
        expect(await base.balanceOf(lp.address)).to.eq(
          initialCollateral
            .sub(depositCollateralValue)
            .add(withdrawCollateralValue),
        );
      });
    });

    it('should revert if msg.sender != p.operator', async () => {
      const { pool, deployer, pKey } = await loadFixture(deploy_CALL);

      await expect(
        pool.connect(deployer).withdraw(pKey, THREE_ETHER, 0, parseEther('1')),
      ).to.be.revertedWithCustomError(pool, 'Pool__NotAuthorized');
    });

    it('should revert if marketPrice is below minMarketPrice or above maxMarketPrice', async () => {
      const { pool, lp, pKey } = await loadFixture(
        deployAndDeposit_1000_LC_CALL,
      );

      expect(await pool.marketPrice()).to.eq(pKey.upper);

      await expect(
        pool
          .connect(lp)
          .withdraw(pKey, THREE_ETHER, pKey.upper.add(1), pKey.upper),
      ).to.be.revertedWithCustomError(pool, 'Pool__AboveMaxSlippage');

      await expect(
        pool
          .connect(lp)
          .withdraw(pKey, THREE_ETHER, pKey.upper.sub(10), pKey.upper.sub(1)),
      ).to.be.revertedWithCustomError(pool, 'Pool__AboveMaxSlippage');
    });

    it('should revert if zero size', async () => {
      const { pool, lp, pKey } = await loadFixture(deploy_CALL);

      await expect(
        pool.connect(lp).withdraw(pKey, 0, 0, parseEther('1')),
      ).to.be.revertedWithCustomError(pool, 'Pool__ZeroSize');
    });

    it('should revert if option is expired', async () => {
      const { pool, lp, pKey, maturity } = await loadFixture(deploy_CALL);

      await increaseTo(maturity);
      await expect(
        pool.connect(lp).withdraw(pKey, THREE_ETHER, 0, parseEther('1')),
      ).to.be.revertedWithCustomError(pool, 'Pool__OptionExpired');
    });

    it('should revert if position does not exists', async () => {
      const { pool, lp, pKey } = await loadFixture(deploy_CALL);

      await expect(
        pool.connect(lp).withdraw(pKey, THREE_ETHER, 0, parseEther('1')),
      ).to.be.revertedWithCustomError(pool, 'Pool__PositionDoesNotExist');
    });

    it('should revert if range is not valid', async () => {
      const { pool, lp, pKey } = await loadFixture(deploy_CALL);

      await expect(
        pool
          .connect(lp)
          .withdraw({ ...pKey, lower: 0 }, THREE_ETHER, 0, parseEther('1')),
      ).to.be.revertedWithCustomError(pool, 'Pool__InvalidRange');

      await expect(
        pool
          .connect(lp)
          .withdraw({ ...pKey, upper: 0 }, THREE_ETHER, 0, parseEther('1')),
      ).to.be.revertedWithCustomError(pool, 'Pool__InvalidRange');

      await expect(
        pool
          .connect(lp)
          .withdraw(
            { ...pKey, lower: parseEther('0.5'), upper: parseEther('0.25') },
            THREE_ETHER,
            0,
            parseEther('1'),
          ),
      ).to.be.revertedWithCustomError(pool, 'Pool__InvalidRange');

      await expect(
        pool
          .connect(lp)
          .withdraw(
            { ...pKey, lower: parseEther('0.0001') },
            THREE_ETHER,
            0,
            parseEther('1'),
          ),
      ).to.be.revertedWithCustomError(pool, 'Pool__InvalidRange');

      await expect(
        pool
          .connect(lp)
          .withdraw(
            { ...pKey, upper: parseEther('1.01') },
            THREE_ETHER,
            0,
            parseEther('1'),
          ),
      ).to.be.revertedWithCustomError(pool, 'Pool__InvalidRange');
    });

    it('should revert if tick width is invalid', async () => {
      const { pool, lp, pKey } = await loadFixture(deploy_CALL);

      await expect(
        pool
          .connect(lp)
          .withdraw(
            { ...pKey, lower: parseEther('0.2501') },
            THREE_ETHER,
            0,
            parseEther('1'),
          ),
      ).to.be.revertedWithCustomError(pool, 'Pool__TickWidthInvalid');

      await expect(
        pool
          .connect(lp)
          .withdraw(
            { ...pKey, upper: parseEther('0.7501') },
            THREE_ETHER,
            0,
            parseEther('1'),
          ),
      ).to.be.revertedWithCustomError(pool, 'Pool__TickWidthInvalid');
    });
  });

  describe('#writeFrom', () => {
    it('should successfully write 500 options', async () => {
      const { pool, lp, trader, base, initialCollateral } = await loadFixture(
        deployAndMintForLP_CALL,
      );

      const size = parseEther('500');
      const fee = await pool.takerFee(size, 0, true);

      const totalSize = size.add(fee);

      await pool.connect(lp).writeFrom(lp.address, trader.address, size);

      expect(await base.balanceOf(pool.address)).to.eq(totalSize);
      expect(await base.balanceOf(lp.address)).to.eq(
        initialCollateral.sub(totalSize),
      );
      expect(await pool.balanceOf(trader.address, TokenType.LONG)).to.eq(size);
      expect(await pool.balanceOf(trader.address, TokenType.SHORT)).to.eq(0);
      expect(await pool.balanceOf(lp.address, TokenType.LONG)).to.eq(0);
      expect(await pool.balanceOf(lp.address, TokenType.SHORT)).to.eq(size);
    });

    it('should successfully write 500 options on behalf of another address', async () => {
      const { pool, lp, trader, deployer, base, initialCollateral } =
        await loadFixture(deployAndMintForLP_CALL);

      const size = parseEther('500');
      const fee = await pool.takerFee(size, 0, true);

      const totalSize = size.add(fee);

      await pool.connect(lp).setApprovalForAll(deployer.address, true);

      await pool
        .connect(deployer)
        .writeFrom(lp.address, trader.address, parseEther('500'));

      expect(await base.balanceOf(pool.address)).to.eq(totalSize);
      expect(await base.balanceOf(lp.address)).to.eq(
        initialCollateral.sub(totalSize),
      );
      expect(await pool.balanceOf(trader.address, TokenType.LONG)).to.eq(size);
      expect(await pool.balanceOf(trader.address, TokenType.SHORT)).to.eq(0);
      expect(await pool.balanceOf(lp.address, TokenType.LONG)).to.eq(0);
      expect(await pool.balanceOf(lp.address, TokenType.SHORT)).to.eq(size);
    });

    it('should revert if trying to write options of behalf of another address without approval', async () => {
      const { pool, lp, deployer, trader } = await loadFixture(deploy_CALL);

      await expect(
        pool
          .connect(deployer)
          .writeFrom(lp.address, trader.address, parseEther('500')),
      ).to.be.revertedWithCustomError(pool, 'Pool__NotAuthorized');
    });

    it('should revert if size is zero', async () => {
      const { pool, lp, trader } = await loadFixture(deploy_CALL);

      await expect(
        pool.connect(lp).writeFrom(lp.address, trader.address, 0),
      ).to.be.revertedWithCustomError(pool, 'Pool__ZeroSize');
    });

    it('should revert if option is expired', async () => {
      const { pool, lp, trader, maturity } = await loadFixture(deploy_CALL);
      await increaseTo(maturity);

      await expect(
        pool.connect(lp).writeFrom(lp.address, trader.address, 1),
      ).to.be.revertedWithCustomError(pool, 'Pool__OptionExpired');
    });
  });

  describe('#trade', () => {
    it('should successfully buy 500 options', async () => {
      const { pool, trader, base, router } = await loadFixture(
        deployAndDeposit_1000_CS_CALL,
      );

      const tradeSize = parseEther('500');
      const totalPremium = await pool.getTradeQuote(tradeSize, true);

      await base.mint(trader.address, totalPremium);
      await base.connect(trader).approve(router.address, totalPremium);

      await pool
        .connect(trader)
        .trade(tradeSize, true, totalPremium.add(totalPremium.div(10)));

      expect(await pool.balanceOf(trader.address, TokenType.LONG)).to.eq(
        tradeSize,
      );
      expect(await pool.balanceOf(pool.address, TokenType.SHORT)).to.eq(
        tradeSize,
      );
      expect(await base.balanceOf(trader.address)).to.eq(0);
    });

    it('should successfully sell 500 options', async () => {
      const { pool, trader, base, router } = await loadFixture(
        deployAndDeposit_1000_LC_CALL,
      );

      const tradeSize = parseEther('500');
      const totalPremium = await pool.getTradeQuote(tradeSize, false);

      await base.mint(trader.address, tradeSize);
      await base.connect(trader).approve(router.address, tradeSize);

      await pool
        .connect(trader)
        .trade(tradeSize, false, totalPremium.sub(totalPremium.div(10)));

      expect(await pool.balanceOf(trader.address, TokenType.SHORT)).to.eq(
        tradeSize,
      );
      expect(await pool.balanceOf(pool.address, TokenType.LONG)).to.eq(
        tradeSize,
      );
      expect(await base.balanceOf(trader.address)).to.eq(totalPremium);
    });

    it('should revert if trying to buy options and totalPremium is above premiumLimit', async () => {
      const { pool, trader, base, router } = await loadFixture(
        deployAndDeposit_1000_CS_CALL,
      );

      const tradeSize = parseEther('500');
      const totalPremium = await pool.getTradeQuote(tradeSize, true);

      await base.mint(trader.address, totalPremium);
      await base.connect(trader).approve(router.address, totalPremium);

      await expect(
        pool.connect(trader).trade(tradeSize, true, totalPremium.sub(1)),
      ).to.be.revertedWithCustomError(pool, 'Pool__AboveMaxSlippage');
    });

    it('should revert if trying to sell options and totalPremium is below premiumLimit', async () => {
      const { pool, trader, base, router } = await loadFixture(
        deployAndDeposit_1000_LC_CALL,
      );

      const tradeSize = parseEther('500');
      const totalPremium = await pool.getTradeQuote(tradeSize, false);

      await base.mint(trader.address, tradeSize);
      await base.connect(trader).approve(router.address, tradeSize);

      await expect(
        pool.connect(trader).trade(tradeSize, false, totalPremium.add(1)),
      ).to.be.revertedWithCustomError(pool, 'Pool__AboveMaxSlippage');
    });

    it('should revert if trying to buy options and ask liquidity is insufficient', async () => {
      const { pool, trader, depositSize } = await loadFixture(
        deployAndDeposit_1000_CS_CALL,
      );

      await expect(
        pool.connect(trader).trade(depositSize.add(1), true, 0),
      ).to.be.revertedWithCustomError(pool, 'Pool__InsufficientAskLiquidity');
    });

    it('should revert if trying to sell options and bid liquidity is insufficient', async () => {
      const { pool, trader, depositSize } = await loadFixture(
        deployAndDeposit_1000_LC_CALL,
      );

      await expect(
        pool.connect(trader).trade(depositSize.add(1), false, 0),
      ).to.be.revertedWithCustomError(pool, 'Pool__InsufficientBidLiquidity');
    });

    it('should revert if trade size is 0', async () => {
      const { pool, trader } = await loadFixture(deploy_CALL);

      await expect(
        pool.connect(trader).trade(0, true, 0),
      ).to.be.revertedWithCustomError(pool, 'Pool__ZeroSize');
    });

    it('should revert if expired', async () => {
      const { pool, trader, maturity } = await loadFixture(deploy_CALL);
      await increaseTo(maturity);

      await expect(
        pool.connect(trader).trade(1, true, 0),
      ).to.be.revertedWithCustomError(pool, 'Pool__OptionExpired');
    });
  });

  describe('#exercise', () => {
    it('should successfully exercise an ITM option', async () => {
      const {
        pool,
        trader,
        base,
        oracleAdapter,
        maturity,
        feeReceiver,
        totalPremium,
        protocolFees,
      } = await loadFixture(deployAndBuy_CALL);

      await oracleAdapter.mock.quote.returns(parseUnits('1250', 18));

      await increaseTo(maturity);
      await pool.exercise(trader.address);

      const exerciseValue = parseEther(((1250 - 1000) / 1250).toString());
      expect(await base.balanceOf(trader.address)).to.eq(exerciseValue);
      expect(await base.balanceOf(pool.address)).to.eq(
        ONE_ETHER.add(totalPremium).sub(exerciseValue).sub(protocolFees),
      );
      expect(await base.balanceOf(feeReceiver.address)).to.eq(protocolFees);
      expect(await pool.balanceOf(trader.address, TokenType.LONG)).to.eq(0);
      expect(await pool.balanceOf(pool.address, TokenType.SHORT)).to.eq(
        ONE_ETHER,
      );
    });

    it('should not pay any token when exercising an OTM option', async () => {
      const {
        pool,
        trader,
        base,
        oracleAdapter,
        maturity,
        feeReceiver,
        totalPremium,
        protocolFees,
      } = await loadFixture(deployAndBuy_CALL);

      await oracleAdapter.mock.quote.returns(parseUnits('999', 18));

      await increaseTo(maturity);
      await pool.exercise(trader.address);

      const exerciseValue = 0;
      expect(await base.balanceOf(trader.address)).to.eq(exerciseValue);
      expect(await base.balanceOf(pool.address)).to.eq(
        ONE_ETHER.add(totalPremium).sub(exerciseValue).sub(protocolFees),
      );
      expect(await base.balanceOf(feeReceiver.address)).to.eq(protocolFees);
      expect(await pool.balanceOf(trader.address, TokenType.LONG)).to.eq(0);
      expect(await pool.balanceOf(pool.address, TokenType.SHORT)).to.eq(
        ONE_ETHER,
      );
    });

    it('should revert if options is not expired', async () => {
      const { pool, trader } = await loadFixture(deploy_CALL);

      await expect(pool.exercise(trader.address)).to.be.revertedWithCustomError(
        pool,
        'Pool__OptionNotExpired',
      );
    });
  });

  describe('#settle', () => {
    it('should successfully settle an ITM option', async () => {
      const {
        pool,
        trader,
        base,
        oracleAdapter,
        maturity,
        feeReceiver,
        totalPremium,
        takerFee,
        protocolFees,
      } = await loadFixture(deployAndSell_CALL);

      await oracleAdapter.mock.quote.returns(parseUnits('1250', 18));

      await increaseTo(maturity);
      await pool.settle(trader.address);

      const exerciseValue = parseEther(((1250 - 1000) / 1250).toString());
      expect(await base.balanceOf(trader.address)).to.eq(
        ONE_ETHER.add(totalPremium).sub(exerciseValue),
      );
      expect(await base.balanceOf(pool.address)).to.eq(
        exerciseValue.add(takerFee).sub(protocolFees),
      );
      expect(await base.balanceOf(feeReceiver.address)).to.eq(protocolFees);
      expect(await pool.balanceOf(trader.address, TokenType.SHORT)).to.eq(0);
      expect(await pool.balanceOf(pool.address, TokenType.LONG)).to.eq(
        ONE_ETHER,
      );
    });

    it('should successfully settle an OTM option', async () => {
      const {
        pool,
        trader,
        base,
        oracleAdapter,
        maturity,
        feeReceiver,
        totalPremium,
        takerFee,
        protocolFees,
      } = await loadFixture(deployAndSell_CALL);

      await oracleAdapter.mock.quote.returns(parseUnits('999', 18));

      await increaseTo(maturity);
      await pool.settle(trader.address);

      const exerciseValue = BigNumber.from(0);
      expect(await base.balanceOf(trader.address)).to.eq(
        ONE_ETHER.add(totalPremium).sub(exerciseValue),
      );
      expect(await base.balanceOf(pool.address)).to.eq(
        exerciseValue.add(takerFee).sub(protocolFees),
      );
      expect(await base.balanceOf(feeReceiver.address)).to.eq(protocolFees);
      expect(await pool.balanceOf(trader.address, TokenType.SHORT)).to.eq(0);
      expect(await pool.balanceOf(pool.address, TokenType.LONG)).to.eq(
        ONE_ETHER,
      );
    });

    it('should revert if not expired', async () => {
      const { pool, trader } = await loadFixture(deploy_CALL);

      await expect(pool.settle(trader.address)).to.be.revertedWithCustomError(
        pool,
        'Pool__OptionNotExpired',
      );
    });
  });

  describe('#settlePosition', () => {
    it('should successfully settle an ITM option position', async () => {
      const {
        base,
        pool,
        feeReceiver,
        initialCollateral,
        maturity,
        oracleAdapter,
        pKey,
        trader,
        totalPremium,
        protocolFees,
      } = await loadFixture(deployAndBuy_CALL);

      await oracleAdapter.mock.quote.returns(parseUnits('1250', 18));

      await increaseTo(maturity);
      await pool.settlePosition(pKey);

      const exerciseValue = parseEther(((1250 - 1000) / 1250).toString());

      expect(await base.balanceOf(trader.address)).to.eq(0);
      expect(await base.balanceOf(pool.address)).to.eq(exerciseValue);
      expect(await base.balanceOf(pKey.operator)).to.eq(
        initialCollateral
          .add(totalPremium)
          .sub(exerciseValue)
          .sub(protocolFees),
      );
      expect(await base.balanceOf(feeReceiver.address)).to.eq(protocolFees);

      expect(await pool.balanceOf(trader.address, TokenType.LONG)).to.eq(
        ONE_ETHER,
      );
      expect(await pool.balanceOf(pool.address, TokenType.SHORT)).to.eq(0);
    });

    it('should successfully settle an OTM option position', async () => {
      const {
        base,
        pool,
        feeReceiver,
        maturity,
        oracleAdapter,
        pKey,
        trader,
        initialCollateral,
        totalPremium,
        protocolFees,
      } = await loadFixture(deployAndBuy_CALL);

      await oracleAdapter.mock.quote.returns(parseUnits('999', 18));

      await increaseTo(maturity);
      await pool.settlePosition(pKey);

      const exerciseValue = BigNumber.from(0);

      expect(await base.balanceOf(trader.address)).to.eq(0);
      expect(await base.balanceOf(pool.address)).to.eq(exerciseValue);
      expect(await base.balanceOf(pKey.operator)).to.eq(
        initialCollateral
          .add(totalPremium)
          .sub(exerciseValue)
          .sub(protocolFees),
      );
      expect(await base.balanceOf(feeReceiver.address)).to.eq(protocolFees);

      expect(await pool.balanceOf(trader.address, TokenType.LONG)).to.eq(
        ONE_ETHER,
      );
      expect(await pool.balanceOf(pool.address, TokenType.SHORT)).to.eq(0);
    });

    it('should revert if not expired', async () => {
      const { pool, pKey } = await loadFixture(deploy_CALL);

      await expect(pool.settlePosition(pKey)).to.be.revertedWithCustomError(
        pool,
        'Pool__OptionNotExpired',
      );
    });
  });

  describe('#fillQuote', () => {
    it('should successfully fill a valid quote', async () => {
      const { base, pool, lp, trader, getTradeQuote, initialCollateral } =
        await loadFixture(deployAndMintForTraderAndLP_CALL);

      const quote = await getTradeQuote();

      const sig = await signQuote(lp.provider!, pool.address, quote);

      await pool.connect(trader).fillQuote(quote, quote.size, sig);

      const premium = BigNumber.from(quote.price).mul(
        bnToNumber(BigNumber.from(quote.size)),
      );

      const protocolFee = await pool.takerFee(quote.size, premium, true);

      expect(await base.balanceOf(lp.address)).to.eq(
        initialCollateral.sub(quote.size).add(premium).sub(protocolFee),
      );
      expect(await base.balanceOf(trader.address)).to.eq(
        initialCollateral.sub(premium),
      );

      expect(await pool.balanceOf(trader.address, TokenType.SHORT)).to.eq(0);
      expect(await pool.balanceOf(trader.address, TokenType.LONG)).to.eq(
        quote.size,
      );

      expect(await pool.balanceOf(lp.address, TokenType.SHORT)).to.eq(
        quote.size,
      );
      expect(await pool.balanceOf(lp.address, TokenType.LONG)).to.eq(0);
    });

    it('should revert if quote is expired', async () => {
      const { pool, lp, trader, getTradeQuote } = await loadFixture(
        deploy_CALL,
      );

      const quote = await getTradeQuote();
      quote.deadline = BigNumber.from((await latest()) - 1);

      const sig = await signQuote(lp.provider!, pool.address, quote);

      await expect(
        pool.connect(trader).fillQuote(quote, quote.size, sig),
      ).to.be.revertedWithCustomError(pool, 'Pool__QuoteExpired');
    });

    it('should revert if quote price is out of bounds', async () => {
      const { pool, lp, trader, getTradeQuote } = await loadFixture(
        deploy_CALL,
      );

      const quote = await getTradeQuote();
      quote.price = BigNumber.from(1);

      let sig = await signQuote(lp.provider!, pool.address, quote);

      await expect(
        pool.connect(trader).fillQuote(quote, quote.size, sig),
      ).to.be.revertedWithCustomError(pool, 'Pool__OutOfBoundsPrice');

      quote.price = parseEther('1').add(1);
      sig = await signQuote(lp.provider!, pool.address, quote);

      await expect(
        pool.connect(trader).fillQuote(quote, quote.size, sig),
      ).to.be.revertedWithCustomError(pool, 'Pool__OutOfBoundsPrice');
    });

    it('should revert if quote is used by someone else than taker', async () => {
      const { pool, lp, trader, deployer, getTradeQuote } = await loadFixture(
        deploy_CALL,
      );

      const quote = await getTradeQuote();
      quote.taker = trader.address;

      const sig = await signQuote(lp.provider!, pool.address, quote);

      await expect(
        pool.connect(deployer).fillQuote(quote, quote.size, sig),
      ).to.be.revertedWithCustomError(pool, 'Pool__InvalidQuoteTaker');
    });

    it('should revert if quote is over filled', async () => {
      const { pool, lp, deployer, trader, getTradeQuote } = await loadFixture(
        deployAndMintForTraderAndLP_CALL,
      );

      const quote = await getTradeQuote();

      const sig = await signQuote(lp.provider!, pool.address, quote);

      await pool
        .connect(trader)
        .fillQuote(quote, BigNumber.from(quote.size).div(2), sig);

      await expect(
        pool.connect(deployer).fillQuote(quote, quote.size, sig),
      ).to.be.revertedWithCustomError(pool, 'Pool__QuoteOverfilled');
    });

    it('should revert if signed message does not match quote', async () => {
      const { pool, lp, trader, getTradeQuote } = await loadFixture(
        deploy_CALL,
      );

      const quote = await getTradeQuote();

      const sig = await signQuote(lp.provider!, pool.address, quote);

      await expect(
        pool
          .connect(trader)
          .fillQuote(
            { ...quote, size: BigNumber.from(quote.size).mul(2).toString() },
            quote.size,
            sig,
          ),
      ).to.be.revertedWithCustomError(pool, 'Pool__InvalidQuoteSignature');
    });
  });

  describe('#cancelTradeQuotes', async () => {
    it('should successfully cancel a trade quote', async () => {
      const { pool, lp, trader, getTradeQuote } = await loadFixture(
        deploy_CALL,
      );

      const quote = await getTradeQuote();

      const sig = await signQuote(lp.provider!, pool.address, quote);

      await pool
        .connect(lp)
        .cancelTradeQuotes([
          await calculateQuoteHash(lp.provider!, quote, pool.address),
        ]);

      await expect(
        pool.connect(trader).fillQuote(quote, quote.size, sig),
      ).to.be.revertedWithCustomError(pool, 'Pool__QuoteCancelled');
    });
  });

  describe('#getTradeQuoteFilledAmount', async () => {
    it('should successfully return filled amount of a trade quote', async () => {
      const { pool, lp, trader, getTradeQuote } = await loadFixture(
        deployAndMintForTraderAndLP_CALL,
      );

      const quote = await getTradeQuote();

      const sig = await signQuote(lp.provider!, pool.address, quote);

      await pool.connect(trader).fillQuote(quote, quote.size.div(2), sig);

      const tradeQuoteHash = await calculateQuoteHash(
        lp.provider!,
        quote,
        pool.address,
      );
      expect(
        await pool.getTradeQuoteFilledAmount(quote.provider, tradeQuoteHash),
      ).to.eq(quote.size.div(2));
    });
  });

  describe('#getClaimableFees', async () => {
    it('should successfully return amount of claimable fees', async () => {
      const { pool, lp, pKey, takerFee } = await loadFixture(deployAndBuy_CALL);

      expect(await pool.connect(lp).getClaimableFees(pKey)).to.eq(
        takerFee
          .mul(parseEther(protocolFeePercentage.toString()))
          .div(ONE_ETHER),
      );
    });
  });

  describe('#claim', () => {
    it('should successfully claim fees', async () => {
      const {
        base,
        pool,
        lp,
        trader,
        pKey,
        feeReceiver,
        initialCollateral,
        tradeSize,
        totalPremium,
        protocolFees,
      } = await loadFixture(deployAndBuy_CALL);

      const claimableFees = await pool.getClaimableFees(pKey);

      await pool.connect(lp).claim(pKey);

      expect(await base.balanceOf(pKey.operator)).to.eq(
        initialCollateral.sub(tradeSize).add(claimableFees),
      );
      expect(await base.balanceOf(pool.address)).to.eq(
        ONE_ETHER.add(totalPremium).sub(claimableFees).sub(protocolFees),
      );
      expect(await base.balanceOf(feeReceiver.address)).to.eq(protocolFees);

      expect(await pool.balanceOf(trader.address, TokenType.LONG)).to.eq(
        ONE_ETHER,
      );
      expect(await pool.balanceOf(pool.address, TokenType.SHORT)).to.eq(
        ONE_ETHER,
      );
    });
  });

  describe('#formatTokenId', () => {
    it('should properly format token id', async () => {
      const { pool } = await loadFixture(deploy_CALL);

      const operator = '0x1000000000000000000000000000000000000001';
      const tokenId = await pool.formatTokenId(
        operator,
        parseEther('0.001'),
        parseEther('1'),
        OrderType.LC,
      );

      expect(
        formatTokenId({
          version: 1,
          operator,
          lower: parseEther('0.001'),
          upper: parseEther('1'),
          orderType: OrderType.LC,
        }),
      ).to.eq(tokenId);

      console.log(tokenId.toHexString());

      expect(tokenId.mask(10)).to.eq(1);
      expect(tokenId.shr(10).mask(10)).to.eq(1000);
      expect(tokenId.shr(20).mask(160)).to.eq(operator);
      expect(tokenId.shr(180).mask(4)).to.eq(2);
      expect(tokenId.shr(252).mask(4)).to.eq(1);
    });
  });

  describe('#parseTokenId', () => {
    it('should properly parse token id', async () => {
      const { pool } = await loadFixture(deploy_CALL);

      const tokenId = BigNumber.from(
        '0x10000000000000000021000000000000000000000000000000000000001fa001',
      );

      const r = await pool.parseTokenId(tokenId);

      const parsed = parseTokenId(tokenId);

      expect(r.lower).to.eq(parsed.lower);
      expect(r.upper).to.eq(parsed.upper);
      expect(r.operator).to.eq(parsed.operator);
      expect(r.orderType).to.eq(parsed.orderType);
      expect(r.version).to.eq(parsed.version);

      expect(r.lower).to.eq(parseEther('0.001'));
      expect(r.upper).to.eq(parseEther('1'));
      expect(r.operator).to.eq('0x1000000000000000000000000000000000000001');
      expect(r.orderType).to.eq(OrderType.LC);
      expect(r.version).to.eq(1);
    });
  });

  describe('#transferPosition', () => {
    it('should successfully partially transfer position to new owner with same operator', async () => {
      const { pool, depositSize, lp, pKey, tokenId, trader } =
        await loadFixture(deployAndDeposit_1000_CS_CALL);

      const transferAmount = parseEther('200');

      await pool
        .connect(lp)
        .transferPosition(pKey, trader.address, pKey.operator, transferAmount);

      expect(await pool.balanceOf(lp.address, tokenId)).to.eq(
        depositSize.sub(transferAmount),
      );
      expect(await pool.balanceOf(trader.address, tokenId)).to.eq(
        transferAmount,
      );
    });

    it('should successfully partially transfer position to new owner with new operator', async () => {
      const { pool, depositSize, lp, pKey, tokenId, trader } =
        await loadFixture(deployAndDeposit_1000_CS_CALL);

      const transferAmount = parseEther('200');

      await pool
        .connect(lp)
        .transferPosition(pKey, trader.address, trader.address, transferAmount);

      expect(await pool.balanceOf(lp.address, tokenId)).to.eq(
        depositSize.sub(transferAmount),
      );

      expect(await pool.balanceOf(trader.address, tokenId)).to.eq(0);

      const newTokenId = formatTokenId({
        version: 1,
        orderType: pKey.orderType,
        operator: trader.address,
        upper: pKey.upper,
        lower: pKey.lower,
      });

      expect(await pool.balanceOf(trader.address, newTokenId)).to.eq(
        transferAmount,
      );
    });

    it('should successfully fully transfer position to new owner with same operator', async () => {
      const { pool, depositSize, lp, pKey, tokenId, trader } =
        await loadFixture(deployAndDeposit_1000_CS_CALL);

      await pool
        .connect(lp)
        .transferPosition(pKey, trader.address, pKey.operator, depositSize);

      expect(await pool.balanceOf(lp.address, tokenId)).to.eq(0);
      expect(await pool.balanceOf(trader.address, tokenId)).to.eq(depositSize);
    });

    it('should successfully fully transfer position to new owner with new operator', async () => {
      const { pool, depositSize, lp, pKey, tokenId, trader } =
        await loadFixture(deployAndDeposit_1000_CS_CALL);

      await pool
        .connect(lp)
        .transferPosition(pKey, trader.address, trader.address, depositSize);

      expect(await pool.balanceOf(lp.address, tokenId)).to.eq(0);

      expect(await pool.balanceOf(trader.address, tokenId)).to.eq(0);

      const newTokenId = formatTokenId({
        version: 1,
        orderType: pKey.orderType,
        operator: trader.address,
        upper: pKey.upper,
        lower: pKey.lower,
      });

      expect(await pool.balanceOf(trader.address, newTokenId)).to.eq(
        depositSize,
      );
    });

    it('should revert if not operator', async () => {
      const { pool, lp, pKey, trader } = await loadFixture(
        deployAndDeposit_1000_CS_CALL,
      );

      const transferAmount = parseEther('200');

      await pool
        .connect(lp)
        .transferPosition(pKey, trader.address, pKey.operator, transferAmount);

      await expect(
        pool
          .connect(trader)
          .transferPosition(pKey, lp.address, pKey.operator, transferAmount),
      ).to.be.revertedWithCustomError(pool, 'Pool__NotAuthorized');
    });

    it('should revert if transferring to same owner and operator', async () => {
      const { pool, depositSize, lp, pKey } = await loadFixture(
        deployAndDeposit_1000_CS_CALL,
      );

      await expect(
        pool
          .connect(lp)
          .transferPosition(pKey, lp.address, lp.address, depositSize),
      ).to.be.revertedWithCustomError(pool, 'Pool__InvalidTransfer');
    });

    it('should revert if size is 0', async () => {
      const { pool, lp, trader, pKey } = await loadFixture(
        deployAndDeposit_1000_CS_CALL,
      );

      await expect(
        pool.connect(lp).transferPosition(pKey, trader.address, lp.address, 0),
      ).to.be.revertedWithCustomError(pool, 'Pool__ZeroSize');
    });

    it('should revert if not enough tokens to transfer', async () => {
      const { pool, lp, trader, pKey, depositSize } = await loadFixture(
        deployAndDeposit_1000_CS_CALL,
      );

      await expect(
        pool
          .connect(lp)
          .transferPosition(
            pKey,
            trader.address,
            lp.address,
            depositSize.add(1),
          ),
      ).to.be.revertedWithCustomError(pool, 'Pool__NotEnoughTokens');
    });
  });

  describe('#safeTransferFrom', () => {
    it('should successfully transfer a long token', async () => {
      const f = await loadFixture(deployAndBuy_CALL);

      expect(await f.pool.balanceOf(f.trader.address, TokenType.LONG)).to.eq(
        ONE_ETHER,
      );
      expect(await f.pool.balanceOf(f.deployer.address, TokenType.LONG)).to.eq(
        0,
      );

      const transferAmount = parseEther('0.3');

      await f.pool
        .connect(f.trader)
        .safeTransferFrom(
          f.trader.address,
          f.deployer.address,
          TokenType.LONG,
          transferAmount,
          '0x',
        );

      expect(await f.pool.balanceOf(f.trader.address, TokenType.LONG)).to.eq(
        ONE_ETHER.sub(transferAmount),
      );
      expect(await f.pool.balanceOf(f.deployer.address, TokenType.LONG)).to.eq(
        transferAmount,
      );
    });

    it('should successfully transfer a short token', async () => {
      const f = await loadFixture(deployAndSell_CALL);

      expect(await f.pool.balanceOf(f.trader.address, TokenType.SHORT)).to.eq(
        ONE_ETHER,
      );
      expect(await f.pool.balanceOf(f.deployer.address, TokenType.SHORT)).to.eq(
        0,
      );

      const transferAmount = parseEther('0.3');

      await f.pool
        .connect(f.trader)
        .safeTransferFrom(
          f.trader.address,
          f.deployer.address,
          TokenType.SHORT,
          transferAmount,
          '0x',
        );

      expect(await f.pool.balanceOf(f.trader.address, TokenType.SHORT)).to.eq(
        ONE_ETHER.sub(transferAmount),
      );
      expect(await f.pool.balanceOf(f.deployer.address, TokenType.SHORT)).to.eq(
        transferAmount,
      );
    });

    it('should revert if trying to transfer LP position', async () => {
      const { pool, lp, tokenId, trader } = await loadFixture(
        deployAndDeposit_1000_CS_CALL,
      );

      await expect(
        pool
          .connect(lp)
          .safeTransferFrom(
            lp.address,
            trader.address,
            tokenId,
            parseEther('200'),
            '0x',
          ),
      ).to.be.revertedWithCustomError(
        pool,
        'Pool__UseTransferPositionToTransferLPTokens',
      );
    });
  });
});
