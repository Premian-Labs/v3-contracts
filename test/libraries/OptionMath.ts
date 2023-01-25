import { expect } from 'chai';
import { ethers } from 'hardhat';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address';
import { OptionMathMock, OptionMathMock__factory } from '../../typechain';
import { parseEther } from 'ethers/lib/utils';

describe('OptionMath', () => {
  let deployer: SignerWithAddress;
  let instance: OptionMathMock;

  before(async function () {
    [deployer] = await ethers.getSigners();
    instance = await new OptionMathMock__factory(deployer).deploy();
  });

  describe('calculateStrikeInterval(int256)', () => {
    it('should return correct strike interval between 1E18 and 9999E18', async () => {
      let strike = parseEther('1');
      let increment = strike;

      let interval = strike.div(10);
      let limit = parseEther('9999');

      while (strike.lte(limit)) {
        let y = await instance.calculateStrikeInterval(strike);

        if (strike.lt(interval.mul(50))) {
          expect(y).to.eq(interval);
        } else {
          expect(y).to.eq(interval.mul(5));
        }

        strike = strike.add(increment);

        if (strike.eq(interval.mul(100))) {
          interval = interval.mul(10);
        }
      }
    });

    it('should return 1000 between 10000 and 49999', async () => {
      for (let x of [
        [10000, 1000],
        [10001, 1000],
        [35321, 1000],
        [49999, 1000],
      ]) {
        let strike = parseEther(x[0].toString());
        let interval = await instance.calculateStrikeInterval(strike);

        expect(interval).to.eq(parseEther(x[1].toString()));
      }
    });

    it('should return 5000 between 50000 and 99999', async () => {
      for (let x of [
        [50000, 5000],
        [50001, 5000],
        [64312, 5000],
        [99999, 5000],
      ]) {
        let strike = parseEther(x[0].toString());
        let interval = await instance.calculateStrikeInterval(strike);

        expect(interval).to.eq(parseEther(x[1].toString()));
      }
    });

    it('should return 10000 between 100000 and 499999', async () => {
      for (let x of [
        [100000, 10000],
        [100001, 10000],
        [256110, 10000],
        [499999, 10000],
      ]) {
        let strike = parseEther(x[0].toString());
        let interval = await instance.calculateStrikeInterval(strike);

        expect(interval).to.eq(parseEther(x[1].toString()));
      }
    });

    it('should return 50000 between 500000 and 999999', async () => {
      for (let x of [
        [500000, 50000],
        [500001, 50000],
        [862841, 50000],
        [999999, 50000],
      ]) {
        let strike = parseEther(x[0].toString());
        let interval = await instance.calculateStrikeInterval(strike);

        expect(interval).to.eq(parseEther(x[1].toString()));
      }
    });

    it('should return 100000 between 1000000 and 4999999', async () => {
      for (let x of [
        [1000000, 100000],
        [1000001, 100000],
        [4321854, 100000],
        [4999999, 100000],
      ]) {
        let strike = parseEther(x[0].toString());
        let interval = await instance.calculateStrikeInterval(strike);

        expect(interval).to.eq(parseEther(x[1].toString()));
      }
    });

    it('should return 500000 between 5000000 and 9999999', async () => {
      for (let x of [
        [5000000, 500000],
        [5000001, 500000],
        [9418355, 500000],
        [9999999, 500000],
      ]) {
        let strike = parseEther(x[0].toString());
        let interval = await instance.calculateStrikeInterval(strike);

        expect(interval).to.eq(parseEther(x[1].toString()));
      }
    });
  });
});
