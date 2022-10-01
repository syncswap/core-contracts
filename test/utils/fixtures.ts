import { Contract } from "ethers";

/**
 * A lightweight implementation of Waffle-like Fixtures.
 * 
 * See https://ethereum-waffle.readthedocs.io/en/latest/fixtures.html
 */
export abstract class Fixtures {
    /**
     * Map that stores names and deployed contract instances (fixtures).
     */
    public static fixtureMap: Map<string, Contract> = new Map();

    /**
     * Sets a fixture with its name and deployed contract instance.
     * @param name The name of fixture.
     * @param contract The deployed contract instance of fixture.
     * @returns The same contract instance.
     */
    public static set(name: string, contract: Contract): Contract {
        if (this.fixtureMap.has(name)) {
            //throw Error(`Duplicate set fixture for ${name}`);
        }
        this.fixtureMap.set(name, contract);
        return contract;
    }

    /**
     * Uses the deployed contract instance of a specific fixture.
     * @param name The name of fixture to use.
     * @returns The contract instance of desired fixture.
     */
    public static use(name: string): Contract {
        return this.fixtureMap.get(name)!;
    }
}