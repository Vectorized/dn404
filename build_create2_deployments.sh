# Download the libs if they aren't yet downloaded.
forge install;

# Format the files.
forge fmt;

# Create the create2 deployments directory.
mkdir create2 > /dev/null 2>&1;

# Use a temporary directory.
mkdir .tmp > /dev/null 2>&1;
rm -rf .tmp/src > /dev/null 2>&1;
rm -rf .tmp/contracts > /dev/null 2>&1;
rm -rf .tmp/lib > /dev/null 2>&1;
cp -r src .tmp/src;
cp -r contracts .tmp/contracts;
cp -r foundry.toml .tmp/foundry.toml;
cp -r remappings.txt .tmp/remappings.txt;
cp -r lib .tmp/lib;

# Go into the temporary directory. 
cd .tmp;

# Build the Solidity files.
forge build --out="out" --root=".";

# Install some files for computing the initcodehash.
echo '{ "devDependencies": { "@ethersproject/keccak256": "5.7.0" } }' > package.json;
if [ ! -f package-lock.json ]; then npm install; fi

# Create the deployments directory in the temporary directory.
mkdir create2 > /dev/null 2>&1;

# Function to generate the deployment files.
generateDeployment() {
    rm -rf "create2/$1" > /dev/null 2>&1;
    mkdir "create2/$1" > /dev/null 2>&1;
    # Generate the js file to do the hard work.
    echo "
    const fs = require(\"fs\"), 
    rfs = s => fs.readFileSync(s, { encoding: \"utf8\", flag: \"r\" });
    const solcOutput = JSON.parse(rfs(\"out/$1.sol/$1.json\"));
    const initcode = solcOutput[\"bytecode\"][\"object\"].slice(2);
    const d = \"create2/$1\";
    fs.writeFileSync(d + \"/initcode.txt\", initcode);
    const t = solcOutput[\"metadata\"][\"settings\"][\"compilationTarget\"], k = Object.keys(t)[0];
    fs.writeFileSync(d + \"/t\", k + \":\" + t[k]);
    fs.writeFileSync(d + \"/initcodehash.txt\", require(\"@ethersproject/keccak256\").keccak256(\"0x\" + initcode));
    " > "extract_$1.js";
    # Run the js file.
    node "extract_$1.js";
    # Generate the standard json verification file.
    forge verify-contract $(cast --address-zero) "$(<create2/$1/t)" --show-standard-json-input > "create2/$1/input.json";
    # Remove the temporary files.
    rm "create2/$1/t" > /dev/null 2>&1;
    rm "extract_$1.js" > /dev/null 2>&1;
    # Move the directory over to the actual deployment directory.
    rm -rf "../create2/$1" > /dev/null 2>&1;
    cp -r "create2/$1" "../create2/$1";
    rm -rf "create2/$1" > /dev/null 2>&1;
    echo "$1 initcodehash:";
    cat "../create2/$1/initcodehash.txt";
    echo "";
}

# Generate the deployments.
generateDeployment "AsterixMirror";
generateDeployment "Asterix";

