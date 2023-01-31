import { expect } from 'chai';
import { ethers } from 'hardhat';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address';
import { PositionMock, PositionMock__factory } from '../../typechain';
import { formatEther, parseEther } from 'ethers/lib/utils';
import { average } from '../../utils/math';

describe('Position', () => {
  let deployer: SignerWithAddress;
  let instance: PositionMock;

  let strike = parseEther('1000');
  let isCall = true;

  let key: any;

  let WAD = parseEther('1');

  enum OrderType {
    CSUP,
    CS,
    LC,
  }

  before(async () => {
    [deployer] = await ethers.getSigners();
    instance = await new PositionMock__factory(deployer).deploy();
  });

  beforeEach(async () => {
    key = {
      owner: deployer.address,
      operator: deployer.address,
      lower: parseEther('0.25'),
      upper: parseEther('0.75'),
      orderType: 0,
      isCall: isCall,
      strike: strike,
    };
  });

  describe('#keyHash', () => {
    it('should return key hash', async () => {
      const keyHash = ethers.utils.keccak256(
        ethers.utils.defaultAbiCoder.encode(
          ['address', 'address', 'uint256', 'uint256', 'uint8'],
          [key.owner, key.operator, key.lower, key.upper, key.orderType],
        ),
      );

      expect(await instance.keyHash(key)).to.eq(keyHash);
    });
  });

  describe('#isShort', () => {
    it('should return true if orderType is short', async () => {
      expect(await instance.isShort(OrderType.CS)).is.true;
      expect(await instance.isShort(OrderType.CSUP)).is.true;
    });

    it('should return false if orderType is not short', async () => {
      expect(await instance.isShort(OrderType.LC)).is.false;
    });
  });

  describe('#isLong', () => {
    it('should return true if orderType is long', async () => {
      expect(await instance.isLong(OrderType.LC)).is.true;
    });

    it('should return true if orderType is not long', async () => {
      expect(await instance.isLong(OrderType.CS)).is.false;
      expect(await instance.isLong(OrderType.CSUP)).is.false;
    });
  });

  describe('#pieceWiseLinear', () => {
    it('should return 0 if lower >= price', async () => {
      expect(await instance.pieceWiseLinear(key, key.lower)).to.eq(0);
      expect(await instance.pieceWiseLinear(key, key.lower.sub(1))).to.eq(0);
    });

    for (const c of [
      ['0.3', '0.1'],
      ['0.5', '0.5'],
      ['0.7', '0.9'],
    ]) {
      it(`should return ${c[1]} for price ${c[0]} if lower < price && price < upper`, async () => {
        expect(await instance.pieceWiseLinear(key, parseEther(c[0]))).to.eq(
          parseEther(c[1]),
        );
      });
    }

    it('should return WAD if price > upper', async () => {
      expect(await instance.pieceWiseLinear(key, key.upper)).to.eq(WAD);
      expect(await instance.pieceWiseLinear(key, key.upper.add(1))).to.eq(WAD);
    });

    it('should revert if lower >= upper', async () => {
      key.lower = key.upper;

      await expect(
        instance.pieceWiseLinear(key, 0),
      ).to.be.revertedWithCustomError(
        instance,
        'Position__LowerGreaterOrEqualUpper',
      );

      key.lower = key.upper.add(1);

      await expect(
        instance.pieceWiseLinear(key, 0),
      ).to.be.revertedWithCustomError(
        instance,
        'Position__LowerGreaterOrEqualUpper',
      );
    });
  });

  describe('#pieceWiseQuadratic', async () => {
    it('should return 0 if lower >= price', async () => {
      expect(await instance.pieceWiseQuadratic(key, key.lower)).to.eq(0);
      expect(await instance.pieceWiseQuadratic(key, key.lower.sub(1))).to.eq(0);
    });

    for (let c of [
      ['0.3', '0.0275'],
      ['0.5', '0.1875'],
      ['0.7', '0.4275'],
    ]) {
      it(`should return ${c[1]} for price ${c[0]} if lower < price && price < upper`, async () => {
        expect(await instance.pieceWiseQuadratic(key, parseEther(c[0]))).to.eq(
          parseEther(c[1]),
        );
      });
    }

    it('should return average price if price >= upper', async () => {
      expect(await instance.pieceWiseQuadratic(key, key.upper)).to.eq(
        average(key.lower, key.upper),
      );

      expect(await instance.pieceWiseQuadratic(key, key.upper.add(1))).to.eq(
        average(key.lower, key.upper),
      );
    });

    it('should revert if lower >= upper', async () => {
      key.lower = key.upper;

      await expect(
        instance.pieceWiseQuadratic(key, 0),
      ).to.be.revertedWithCustomError(
        instance,
        'Position__LowerGreaterOrEqualUpper',
      );

      key.lower = key.upper.add(1);

      await expect(
        instance.pieceWiseQuadratic(key, 0),
      ).to.be.revertedWithCustomError(
        instance,
        'Position__LowerGreaterOrEqualUpper',
      );
    });
  });

  describe('#collateralToContracts', () => {
    const cases = [
      ['1', '0.001'],
      ['77', '0.77'],
      ['344', '0.344'],
      ['5235', '5.235'],
      ['99999', '99.999'],
    ];

    describe('#call options', () => {
      for (let c of cases) {
        let collateral = parseEther(c[0]);
        let contracts = collateral;

        it(`should return ${c[0]} contract(s) for ${c[0]} uint(s) of collateral`, async () => {
          expect(
            await instance.collateralToContracts(collateral, strike, isCall),
          ).to.eq(contracts);
        });
      }
    });

    describe('#put options', () => {
      for (let c of cases) {
        let collateral = parseEther(c[0]);
        let contracts = collateral.mul(parseEther('1')).div(strike);
        let formattedContracts = formatEther(contracts);

        it(`should return ${formattedContracts} contract(s) for ${c[0]} uint(s) of collateral`, async () => {
          expect(
            await instance.collateralToContracts(collateral, strike, !isCall),
          ).to.eq(contracts);
        });
      }
    });
  });

  describe('#contractsToCollateral', () => {
    const cases = [
      ['1', '0.001'],
      ['77', '0.77'],
      ['344', '0.344'],
      ['5235', '5.235'],
      ['99999', '99.999'],
    ];

    describe('#call options', () => {
      for (let c of cases) {
        let contracts = parseEther(c[0]);
        let collateral = contracts;

        it(`should return ${c[0]} unit(s) of collateral for ${c[0]} contract(s)`, async () => {
          expect(
            await instance.contractsToCollateral(contracts, strike, isCall),
          ).to.eq(collateral);
        });
      }
    });

    describe('#put options', () => {
      for (let c of cases) {
        let contracts = parseEther(c[0]);
        let collateral = contracts.mul(strike).div(parseEther('1'));
        let formattedCollateral = formatEther(collateral);

        it(`should return ${formattedCollateral} unit(s) of collateral for ${c[0]} contract(s)`, async () => {
          expect(
            await instance.contractsToCollateral(contracts, strike, !isCall),
          ).to.eq(collateral);
        });
      }
    });
  });

  describe('#liquidityPerTick', () => {
    for (let c of [
      ['0.25', '0.75', '250', '0.5'],
      ['0.25', '0.75', '500', '1'],
      ['0.25', '0.75', '1000', '2'],
    ]) {
      beforeEach(async () => {
        key.lower = parseEther(c[0]);
        key.upper = parseEther(c[1]);
      });

      it(`should return ${c[3]} for size ${c[2]} and range ${c[0]} - ${c[1]}`, async () => {
        expect(await instance.liquidityPerTick(key, parseEther(c[2]))).to.eq(
          parseEther(c[3]),
        );
      });
    }
  });

  describe('#bid', () => {
    const cases = [
      ['0.5', '0.3', '0.01375'],
      ['1', '0.5', '0.1875'],
      ['2', '0.7', '0.855'],
    ];

    describe('#call options', () => {
      for (let c of cases) {
        let collateral = parseEther(c[2]);

        it(`should return ${c[2]} unit(s) of collateral for size ${c[0]} and price ${c[1]}`, async () => {
          expect(
            await instance.bid(key, parseEther(c[0]), parseEther(c[1])),
          ).to.eq(collateral);
        });
      }
    });

    describe('#put options', () => {
      for (let c of cases) {
        let collateral = parseEther(c[2]).mul(strike).div(parseEther('1'));
        let formattedCollateral = formatEther(collateral);

        beforeEach(async () => {
          key.isCall = !isCall;
        });

        it(`should return ${formattedCollateral} unit(s) of collateral for size ${c[0]} and price ${c[1]}`, async () => {
          expect(
            await instance.bid(key, parseEther(c[0]), parseEther(c[1])),
          ).to.eq(collateral);
        });
      }
    });
  });
});
