import {
  PoolBase__factory,
  PoolCore__factory,
  PoolFactory,
  PoolFactory__factory,
  PoolFactoryProxy__factory,
  Premia,
  Premia__factory,
} from '../typechain';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address';
import { diamondCut } from './utils/diamond';

interface PoolUtilArgs {
  premiaDiamond: Premia;
  poolFactory: PoolFactory;
}

export class PoolUtil {
  premiaDiamond: Premia;
  poolFactory: PoolFactory;

  constructor(args: PoolUtilArgs) {
    this.premiaDiamond = args.premiaDiamond;
    this.poolFactory = args.poolFactory;
  }

  static async deploy(deployer: SignerWithAddress) {
    // Diamond and facets deployment
    const premiaDiamond = await new Premia__factory(deployer).deploy();
    await premiaDiamond.deployed();

    const poolBaseFactory = new PoolBase__factory(deployer);
    const poolBaseImpl = await poolBaseFactory.deploy();
    await poolBaseImpl.deployed();

    const poolCoreFactory = new PoolCore__factory(deployer);
    const poolCoreImpl = await poolCoreFactory.deploy();
    await poolCoreImpl.deployed();

    let registeredSelectors = [
      premiaDiamond.interface.getSighash('supportsInterface(bytes4)'),
    ];

    registeredSelectors = registeredSelectors.concat(
      await diamondCut(
        premiaDiamond,
        poolBaseImpl.address,
        poolBaseFactory,
        registeredSelectors,
      ),
    );

    registeredSelectors = registeredSelectors.concat(
      await diamondCut(
        premiaDiamond,
        poolCoreImpl.address,
        poolCoreFactory,
        registeredSelectors,
      ),
    );

    //////////////////////////////////////////////

    /////////////////
    // PoolFactory //
    /////////////////

    const poolFactoryImpl = await new PoolFactory__factory(deployer).deploy();
    await poolFactoryImpl.deployed();

    const poolFactoryProxy = await new PoolFactoryProxy__factory(
      deployer,
    ).deploy(poolFactoryImpl.address);
    await poolFactoryProxy.deployed();

    const poolFactory = PoolFactory__factory.connect(
      poolFactoryProxy.address,
      deployer,
    );

    return new PoolUtil({ premiaDiamond, poolFactory });
  }
}
