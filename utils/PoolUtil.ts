import {
  PoolBase__factory,
  PoolCore__factory,
  PoolFactory,
  PoolFactory__factory,
  PoolFactoryProxy__factory,
  PoolCoreMock__factory,
  Premia,
  Premia__factory,
  ExchangeHelper__factory,
} from '../typechain';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address';
import { diamondCut } from '../scripts/utils/diamond';
import { BigNumber } from 'ethers';

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

  static async deploy(
    deployer: SignerWithAddress,
    wrappedNativeToken: string,
    nativeUsdOracle: string,
    discountPerPool: BigNumber = BigNumber.from('1' + '0'.repeat(17)), // 10%
    log = true,
    isDevMode = false,
  ) {
    // Diamond and facets deployment
    const premiaDiamond = await new Premia__factory(deployer).deploy();
    await premiaDiamond.deployed();

    if (log) console.log(`Premia Diamond : ${premiaDiamond.address}`);

    //////////////////////////////////////////////

    /////////////////
    // PoolFactory //
    /////////////////

    const poolFactoryImpl = await new PoolFactory__factory(deployer).deploy(
      premiaDiamond.address,
      nativeUsdOracle,
    );
    await poolFactoryImpl.deployed();

    if (log) console.log(`PoolFactory : ${poolFactoryImpl.address}`);

    const poolFactoryProxy = await new PoolFactoryProxy__factory(
      deployer,
    ).deploy(poolFactoryImpl.address, discountPerPool);
    await poolFactoryProxy.deployed();

    if (log) console.log(`PoolFactoryProxy : ${poolFactoryProxy.address}`);

    const poolFactory = PoolFactory__factory.connect(
      poolFactoryProxy.address,
      deployer,
    );

    //////////////////////////////////////////////

    /////////////////
    // Pool //
    /////////////////

    const poolBaseFactory = new PoolBase__factory(deployer);
    const poolBaseImpl = await poolBaseFactory.deploy();
    await poolBaseImpl.deployed();

    if (log) console.log(`PoolBase : ${poolBaseImpl.address}`);

    let poolCoreFactory: PoolCore__factory | PoolCoreMock__factory;

    if (isDevMode) {
      poolCoreFactory = new PoolCoreMock__factory(deployer);
    } else {
      poolCoreFactory = new PoolCore__factory(deployer);
    }

    const exchangeHelper = await new ExchangeHelper__factory(deployer).deploy();

    const poolCoreImpl = await poolCoreFactory.deploy(
      poolFactory.address,
      exchangeHelper.address,
      wrappedNativeToken,
    );
    await poolCoreImpl.deployed();

    if (log)
      console.log(
        `${isDevMode ? 'PoolCoreMock' : 'PoolCore'} : ${poolCoreImpl.address}`,
      );

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

    return new PoolUtil({ premiaDiamond, poolFactory });
  }
}
