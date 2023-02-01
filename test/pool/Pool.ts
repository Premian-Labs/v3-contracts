import { expect } from 'chai';
import { ethers } from 'hardhat';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address';
import {
  ERC20Mock,
  ERC20Mock__factory,
  IPoolMock,
  IPoolMock__factory,
} from '../../typechain';
import { BigNumber } from 'ethers';
import { parseEther } from 'ethers/lib/utils';
import { PoolUtil, TokenType } from '../../utils/PoolUtil';
import {
  deployMockContract,
  MockContract,
} from '@ethereum-waffle/mock-contract';
import {
  getValidMaturity,
  ONE_HOUR,
  revertToSnapshotAfterEach,
} from '../../utils/time';
import { signQuote, TradeQuote } from '../../utils/quote';
import { getCurrentTimestamp } from 'hardhat/internal/hardhat-network/provider/utils/getCurrentTimestamp';
import { bnToNumber } from '../../utils/math';

describe('Pool', () => {
  let deployer: SignerWithAddress;
  let lp: SignerWithAddress;
  let trader: SignerWithAddress;

  let callPool: IPoolMock;
  let putPool: IPoolMock;
  let p: PoolUtil;

  let base: ERC20Mock;
  let underlying: ERC20Mock;
  let baseOracle: MockContract;
  let underlyingOracle: MockContract;

  let strike = parseEther('1000'); // ATM
  let maturity: number;

  let isCall: boolean;
  let collateral: BigNumber;

  let getQuote: () => TradeQuote;

  before(async () => {
    [deployer, lp, trader] = await ethers.getSigners();

    underlying = await new ERC20Mock__factory(deployer).deploy('WETH', 18);
    base = await new ERC20Mock__factory(deployer).deploy('USDC', 6);

    p = await PoolUtil.deploy(deployer, underlying.address, true, true);

    baseOracle = await deployMockContract(deployer as any, [
      'function latestAnswer() external view returns (int256)',
      'function decimals () external view returns (uint8)',
    ]);

    await baseOracle.mock.latestAnswer.returns(100000000);
    await baseOracle.mock.decimals.returns(8);

    underlyingOracle = await deployMockContract(deployer as any, [
      'function latestAnswer() external view returns (int256)',
      'function decimals () external view returns (uint8)',
    ]);

    await underlyingOracle.mock.latestAnswer.returns(100000000000);
    await underlyingOracle.mock.decimals.returns(8);

    maturity = await getValidMaturity(10, 'months');

    for (isCall of [true, false]) {
      const tx = await p.poolFactory.deployPool(
        base.address,
        underlying.address,
        baseOracle.address,
        underlyingOracle.address,
        strike,
        maturity,
        isCall,
      );

      const r = await tx.wait(1);
      const poolAddress = (r as any).events[0].args.poolAddress;

      if (isCall) {
        callPool = IPoolMock__factory.connect(poolAddress, deployer);
        collateral = parseEther('10');
      } else {
        putPool = IPoolMock__factory.connect(poolAddress, deployer);
        collateral = parseEther('1000');
      }
    }

    getQuote = () => {
      return {
        provider: lp.address,
        taker: trader.address,
        price: parseEther('0.1').toString(),
        size: parseEther('10').toString(),
        isBuy: false,
        deadline: getCurrentTimestamp() + ONE_HOUR,
        nonce: 0,
      };
    };
  });

  revertToSnapshotAfterEach(async () => {});

  describe('__internal', function () {
    describe('#_getPricing', () => {
      it('should return pool state', async () => {
        let isBuy = true;
        let args = await callPool._getPricing(isBuy);

        expect(args.liquidityRate).to.eq(0);
        expect(args.marketPrice).to.eq(0);
        expect(args.lower).to.eq(parseEther('0.001'));
        expect(args.upper).to.eq(parseEther('1'));
        expect(args.isBuy).to.eq(isBuy);

        args = await callPool._getPricing(!isBuy);

        expect(args.liquidityRate).to.eq(0);
        expect(args.marketPrice).to.eq(0);
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
          orderType: 2,
          isCall: isCall,
          strike: strike,
        };

        await underlying.connect(lp).approve(callPool.address, collateral);

        const nearestBelow = await callPool.getNearestTicksBelow(lower, upper);

        await underlying.mint(lp.address, parseEther('2000'));

        await callPool
          .connect(lp)
          [
            'deposit((address,address,uint256,uint256,uint8,bool,uint256),uint256,uint256,uint256,uint256)'
          ](
            position,
            nearestBelow.nearestBelowLower,
            nearestBelow.nearestBelowUpper,
            parseEther('2000'),
            0,
          );

        args = await callPool._getPricing(isBuy);

        expect(args.liquidityRate).to.eq(parseEther('4'));
        expect(args.marketPrice).to.eq(upper);
        expect(args.lower).to.eq(lower);
        expect(args.upper).to.eq(upper);
        expect(args.isBuy).to.eq(isBuy);

        args = await callPool._getPricing(!isBuy);

        expect(args.liquidityRate).to.eq(parseEther('4'));
        expect(args.marketPrice).to.eq(upper);
        expect(args.lower).to.eq(lower);
        expect(args.upper).to.eq(upper);
        expect(args.isBuy).to.eq(!isBuy);
      });
    });
  });

  describe('#fillQuote', () => {
    it('should successfully fill a valid quote', async () => {
      const quote = getQuote();

      const initialBalance = parseEther('10');

      await underlying.mint(lp.address, initialBalance);
      await underlying.mint(trader.address, initialBalance);

      await underlying
        .connect(lp)
        .approve(callPool.address, ethers.constants.MaxUint256);
      await underlying
        .connect(trader)
        .approve(callPool.address, ethers.constants.MaxUint256);

      const sig = await signQuote(lp.provider!, callPool.address, quote);

      await callPool
        .connect(trader)
        .fillQuote(quote, quote.size, sig.v, sig.r, sig.s);

      const premium = BigNumber.from(quote.price).mul(
        bnToNumber(BigNumber.from(quote.size)),
      );

      const fee = (await callPool.takerFee(quote.size, premium)).div(2); // Divide by 2 to account for protocol fee

      expect(await underlying.balanceOf(lp.address)).to.eq(
        initialBalance.sub(quote.size).add(premium).sub(fee),
      );
      expect(await underlying.balanceOf(trader.address)).to.eq(
        initialBalance.sub(premium),
      );

      expect(await callPool.balanceOf(trader.address, TokenType.SHORT)).to.eq(
        0,
      );
      expect(await callPool.balanceOf(trader.address, TokenType.LONG)).to.eq(
        parseEther('10'),
      );

      expect(await callPool.balanceOf(lp.address, TokenType.SHORT)).to.eq(
        parseEther('10'),
      );
      expect(await callPool.balanceOf(lp.address, TokenType.LONG)).to.eq(0);
    });

    it('should revert if quote is expired', async () => {
      const quote = getQuote();
      quote.deadline = getCurrentTimestamp() - 1;

      const sig = await signQuote(lp.provider!, callPool.address, quote);

      await expect(
        callPool
          .connect(trader)
          .fillQuote(quote, quote.size, sig.v, sig.r, sig.s),
      ).to.be.revertedWithCustomError(callPool, 'Pool__QuoteExpired');
    });

    it('should revert if quote price is out of bounds', async () => {
      const quote = getQuote();
      quote.price = 1;

      let sig = await signQuote(lp.provider!, callPool.address, quote);

      await expect(
        callPool
          .connect(trader)
          .fillQuote(quote, quote.size, sig.v, sig.r, sig.s),
      ).to.be.revertedWithCustomError(callPool, 'Pool__OutOfBoundsPrice');

      quote.price = parseEther('1').add(1).toString();
      sig = await signQuote(lp.provider!, callPool.address, quote);

      await expect(
        callPool
          .connect(trader)
          .fillQuote(quote, quote.size, sig.v, sig.r, sig.s),
      ).to.be.revertedWithCustomError(callPool, 'Pool__OutOfBoundsPrice');
    });

    it('should revert if quote is not used by someone else than taker', async () => {
      const quote = getQuote();

      const sig = await signQuote(lp.provider!, callPool.address, quote);

      await expect(
        callPool
          .connect(deployer)
          .fillQuote(quote, quote.size, sig.v, sig.r, sig.s),
      ).to.be.revertedWithCustomError(callPool, 'Pool__InvalidQuoteTaker');
    });

    it('should revert if nonce is not the current one', async () => {
      const quote = getQuote();

      await callPool.setNonce(trader.address, 2);

      let sig = await signQuote(lp.provider!, callPool.address, { ...quote });

      await expect(
        callPool
          .connect(trader)
          .fillQuote(quote, quote.size, sig.v, sig.r, sig.s),
      ).to.be.revertedWithCustomError(callPool, 'Pool__InvalidQuoteNonce');

      sig = await signQuote(lp.provider!, callPool.address, {
        ...quote,
        nonce: 10,
      });

      await expect(
        callPool
          .connect(trader)
          .fillQuote(quote, quote.size, sig.v, sig.r, sig.s),
      ).to.be.revertedWithCustomError(callPool, 'Pool__InvalidQuoteNonce');
    });

    it('should revert if signed message does not match quote', async () => {
      const quote = getQuote();

      const sig = await signQuote(lp.provider!, callPool.address, quote);

      await expect(
        callPool
          .connect(trader)
          .fillQuote(
            { ...quote, size: BigNumber.from(quote.size).mul(2).toString() },
            quote.size,
            sig.v,
            sig.r,
            sig.s,
          ),
      ).to.be.revertedWithCustomError(callPool, 'Pool__InvalidQuoteSignature');
    });
  });

  describe('#formatTokenId', () => {
    it('should properly format token id', async () => {
      const operator = '0x1000000000000000000000000000000000000001';
      const tokenId = await callPool.formatTokenId(
        operator,
        parseEther('0.001'),
        parseEther('1'),
        2,
      );

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
      const r = await callPool.parseTokenId(
        BigNumber.from(
          '0x10000000000000000021000000000000000000000000000000000000001fa001',
        ),
      );

      expect(r.lower).to.eq(parseEther('0.001'));
      expect(r.upper).to.eq(parseEther('1'));
      expect(r.operator).to.eq('0x1000000000000000000000000000000000000001');
      expect(r.orderType).to.eq(2);
      expect(r.version).to.eq(1);
    });
  });
});
