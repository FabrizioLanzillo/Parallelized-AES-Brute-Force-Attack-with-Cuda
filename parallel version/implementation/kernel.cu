#include <curand_kernel.h>
#include <curand.h>
#include <device_launch_parameters.h>
#include <stdio.h>
#include <fstream>
#include <cstring>
#include <string.h>
#include <sstream>  
#include <cuda.h>
#include <stdint.h>

using namespace std;

//Encrypting/Decrypting Parameters definition
#define AES_KEYLENGTH 32
#define IV_KEYLENGTH 16
#define SALT_KEYLENGTH 8
#define DEBUG true
#define BLOCK_SIZE 16
#define PLAINTEXT_LENGHT 445
#define AES_keyExpSize 240


// The number of columns comprising a state in AES. This is a constant in AES. Value=4
#define Nb 4
#define Nk 8
#define Nr 14
#define MULTIPLY_AS_A_FUNCTION 0


//Brute Force configuration
#define BASE_NUMBER 2

struct AES_ctx
{
	uint8_t RoundKey[AES_keyExpSize];
	uint8_t Iv[BLOCK_SIZE];

};

//              PARAMETERS
//  Key generated from openssl enc -aes-256-cbc -key_aes secret -P -md sha1
//  salt = B51DE47CC865460E
//  key = 85926BE3DA736F475493C49276ED17D418A55A2CFD077D1215ED251C4A57D8EC
//  85 92 6B E3 DA 73 6F 47 54 93 C4 92 76 ED 17 D4 18 A5 5A 2C FD 07 7D 12 15 ED 25 1C 4A 57 D8 EC  
//  iv = D8596B739EFAC0460E861F9B7790F996
//  iv =D8 59 6B 73 9E FA C0 46 0E 86 1F 9B 77 90 F9 96

//Key in HEX format as global parameters
//static const int key_size = 32;
//const int num_bits_to_hack = 12;
const string plaintext_file = "./../../files/text_files/plaintext.txt";
const string ciphertext_file = "./../../files/text_files/ciphertext.txt";
const string key_aes_hex_file = "./../../files/secret_files/key_aes_hex.txt";
const string key_aes_file = "./../../files/secret_files/key_aes.txt";
//const string key_wrong_file = "key_wrong.txt";
//const string key_wrong_file_hex = "key_wrong_hex.txt";
const string iv_file_hex = "./../../files/secret_files/iv_hex.txt";
const string iv_file = "./../../files/secret_files/iv.txt";
const string salt_file_hex = "./../../files/secret_files/salt_hex.txt";
const string salt_file = "./../../files/secret_files/salt.txt";

/*****************************************************************************/
/* Private variables:                                                        */
/*****************************************************************************/
// state - array holding the intermediate results during decryption.
typedef uint8_t state_t[4][4];

/* ***************************************************************************************************/
/* ******************************************* CONSTANTS *********************************************/
/* ***************************************************************************************************/

// The lookup-tables are marked const so they can be placed in read-only storage instead of RAM
// The numbers below can be computed dynamically trading ROM for RAM - 
// This can be useful in (embedded) bootloader applications, where ROM is often limited.
const uint8_t sbox[256] = {
	//0     1    2      3     4    5     6     7      8    9     A      B    C     D     E     F
	0x63, 0x7c, 0x77, 0x7b, 0xf2, 0x6b, 0x6f, 0xc5, 0x30, 0x01, 0x67, 0x2b, 0xfe, 0xd7, 0xab, 0x76,
	0xca, 0x82, 0xc9, 0x7d, 0xfa, 0x59, 0x47, 0xf0, 0xad, 0xd4, 0xa2, 0xaf, 0x9c, 0xa4, 0x72, 0xc0,
	0xb7, 0xfd, 0x93, 0x26, 0x36, 0x3f, 0xf7, 0xcc, 0x34, 0xa5, 0xe5, 0xf1, 0x71, 0xd8, 0x31, 0x15,
	0x04, 0xc7, 0x23, 0xc3, 0x18, 0x96, 0x05, 0x9a, 0x07, 0x12, 0x80, 0xe2, 0xeb, 0x27, 0xb2, 0x75,
	0x09, 0x83, 0x2c, 0x1a, 0x1b, 0x6e, 0x5a, 0xa0, 0x52, 0x3b, 0xd6, 0xb3, 0x29, 0xe3, 0x2f, 0x84,
	0x53, 0xd1, 0x00, 0xed, 0x20, 0xfc, 0xb1, 0x5b, 0x6a, 0xcb, 0xbe, 0x39, 0x4a, 0x4c, 0x58, 0xcf,
	0xd0, 0xef, 0xaa, 0xfb, 0x43, 0x4d, 0x33, 0x85, 0x45, 0xf9, 0x02, 0x7f, 0x50, 0x3c, 0x9f, 0xa8,
	0x51, 0xa3, 0x40, 0x8f, 0x92, 0x9d, 0x38, 0xf5, 0xbc, 0xb6, 0xda, 0x21, 0x10, 0xff, 0xf3, 0xd2,
	0xcd, 0x0c, 0x13, 0xec, 0x5f, 0x97, 0x44, 0x17, 0xc4, 0xa7, 0x7e, 0x3d, 0x64, 0x5d, 0x19, 0x73,
	0x60, 0x81, 0x4f, 0xdc, 0x22, 0x2a, 0x90, 0x88, 0x46, 0xee, 0xb8, 0x14, 0xde, 0x5e, 0x0b, 0xdb,
	0xe0, 0x32, 0x3a, 0x0a, 0x49, 0x06, 0x24, 0x5c, 0xc2, 0xd3, 0xac, 0x62, 0x91, 0x95, 0xe4, 0x79,
	0xe7, 0xc8, 0x37, 0x6d, 0x8d, 0xd5, 0x4e, 0xa9, 0x6c, 0x56, 0xf4, 0xea, 0x65, 0x7a, 0xae, 0x08,
	0xba, 0x78, 0x25, 0x2e, 0x1c, 0xa6, 0xb4, 0xc6, 0xe8, 0xdd, 0x74, 0x1f, 0x4b, 0xbd, 0x8b, 0x8a,
	0x70, 0x3e, 0xb5, 0x66, 0x48, 0x03, 0xf6, 0x0e, 0x61, 0x35, 0x57, 0xb9, 0x86, 0xc1, 0x1d, 0x9e,
	0xe1, 0xf8, 0x98, 0x11, 0x69, 0xd9, 0x8e, 0x94, 0x9b, 0x1e, 0x87, 0xe9, 0xce, 0x55, 0x28, 0xdf,
	0x8c, 0xa1, 0x89, 0x0d, 0xbf, 0xe6, 0x42, 0x68, 0x41, 0x99, 0x2d, 0x0f, 0xb0, 0x54, 0xbb, 0x16 };


// The round constant word array, Rcon[i], contains the values given by 
// x to the power (i-1) being powers of x (x is denoted as {02}) in the field GF(2^8)
const uint8_t Rcon[11] = {
  0x8d, 0x01, 0x02, 0x04, 0x08, 0x10, 0x20, 0x40, 0x80, 0x1b, 0x36 };

__device__ const uint8_t d_rsbox[256] = {
  0x52, 0x09, 0x6a, 0xd5, 0x30, 0x36, 0xa5, 0x38, 0xbf, 0x40, 0xa3, 0x9e, 0x81, 0xf3, 0xd7, 0xfb,
  0x7c, 0xe3, 0x39, 0x82, 0x9b, 0x2f, 0xff, 0x87, 0x34, 0x8e, 0x43, 0x44, 0xc4, 0xde, 0xe9, 0xcb,
  0x54, 0x7b, 0x94, 0x32, 0xa6, 0xc2, 0x23, 0x3d, 0xee, 0x4c, 0x95, 0x0b, 0x42, 0xfa, 0xc3, 0x4e,
  0x08, 0x2e, 0xa1, 0x66, 0x28, 0xd9, 0x24, 0xb2, 0x76, 0x5b, 0xa2, 0x49, 0x6d, 0x8b, 0xd1, 0x25,
  0x72, 0xf8, 0xf6, 0x64, 0x86, 0x68, 0x98, 0x16, 0xd4, 0xa4, 0x5c, 0xcc, 0x5d, 0x65, 0xb6, 0x92,
  0x6c, 0x70, 0x48, 0x50, 0xfd, 0xed, 0xb9, 0xda, 0x5e, 0x15, 0x46, 0x57, 0xa7, 0x8d, 0x9d, 0x84,
  0x90, 0xd8, 0xab, 0x00, 0x8c, 0xbc, 0xd3, 0x0a, 0xf7, 0xe4, 0x58, 0x05, 0xb8, 0xb3, 0x45, 0x06,
  0xd0, 0x2c, 0x1e, 0x8f, 0xca, 0x3f, 0x0f, 0x02, 0xc1, 0xaf, 0xbd, 0x03, 0x01, 0x13, 0x8a, 0x6b,
  0x3a, 0x91, 0x11, 0x41, 0x4f, 0x67, 0xdc, 0xea, 0x97, 0xf2, 0xcf, 0xce, 0xf0, 0xb4, 0xe6, 0x73,
  0x96, 0xac, 0x74, 0x22, 0xe7, 0xad, 0x35, 0x85, 0xe2, 0xf9, 0x37, 0xe8, 0x1c, 0x75, 0xdf, 0x6e,
  0x47, 0xf1, 0x1a, 0x71, 0x1d, 0x29, 0xc5, 0x89, 0x6f, 0xb7, 0x62, 0x0e, 0xaa, 0x18, 0xbe, 0x1b,
  0xfc, 0x56, 0x3e, 0x4b, 0xc6, 0xd2, 0x79, 0x20, 0x9a, 0xdb, 0xc0, 0xfe, 0x78, 0xcd, 0x5a, 0xf4,
  0x1f, 0xdd, 0xa8, 0x33, 0x88, 0x07, 0xc7, 0x31, 0xb1, 0x12, 0x10, 0x59, 0x27, 0x80, 0xec, 0x5f,
  0x60, 0x51, 0x7f, 0xa9, 0x19, 0xb5, 0x4a, 0x0d, 0x2d, 0xe5, 0x7a, 0x9f, 0x93, 0xc9, 0x9c, 0xef,
  0xa0, 0xe0, 0x3b, 0x4d, 0xae, 0x2a, 0xf5, 0xb0, 0xc8, 0xeb, 0xbb, 0x3c, 0x83, 0x53, 0x99, 0x61,
  0x17, 0x2b, 0x04, 0x7e, 0xba, 0x77, 0xd6, 0x26, 0xe1, 0x69, 0x14, 0x63, 0x55, 0x21, 0x0c, 0x7d };

/* *************************************************************************************************/
/* ******************************************* DEC_FUN *********************************************/
/* *************************************************************************************************/

__device__ void XorWithIv(uint8_t* buf, const uint8_t* Iv)
{
	uint8_t i;
	for (i = 0; i < BLOCK_SIZE; ++i) // The block in AES is always 128bit no matter the key size
	{
		buf[i] ^= Iv[i];
	}
}

/** Extracts a specific value from the SBOX
* num: cell to extract
*/
uint8_t getSBoxValue(uint8_t num)
{
	return sbox[num];
}

/* This function produces Nb(Nr + 1) round keys.The round keys are used in each round to decrypt the states.
* RoundKey: rounded key
* Key: original key
*/
void KeyExpansion(uint8_t* RoundKey, const uint8_t* Key)
{
	unsigned i, j, k;
	uint8_t tempa[4]; // Used for the column/row operations

	// The first round key is the key itself.
	for (i = 0; i < Nk; ++i)
	{
		RoundKey[(i * 4) + 0] = Key[(i * 4) + 0];
		RoundKey[(i * 4) + 1] = Key[(i * 4) + 1];
		RoundKey[(i * 4) + 2] = Key[(i * 4) + 2];
		RoundKey[(i * 4) + 3] = Key[(i * 4) + 3];
	}

	// All other round keys are found from the previous round keys.
	for (i = Nk; i < Nb * (Nr + 1); ++i)
	{
		{
			k = (i - 1) * 4;
			tempa[0] = RoundKey[k + 0];
			tempa[1] = RoundKey[k + 1];
			tempa[2] = RoundKey[k + 2];
			tempa[3] = RoundKey[k + 3];

		}

		if (i % Nk == 0)
		{
			// This function shifts the 4 bytes in a word to the left once.
			// [a0,a1,a2,a3] becomes [a1,a2,a3,a0]

			// Function RotWord()
			{
				const uint8_t u8tmp = tempa[0];
				tempa[0] = tempa[1];
				tempa[1] = tempa[2];
				tempa[2] = tempa[3];
				tempa[3] = u8tmp;
			}

			// SubWord() is a function that takes a four-byte input word and 
			// applies the S-box to each of the four bytes to produce an output word.

			// Function Subword()
			{
				tempa[0] = getSBoxValue(tempa[0]);
				tempa[1] = getSBoxValue(tempa[1]);
				tempa[2] = getSBoxValue(tempa[2]);
				tempa[3] = getSBoxValue(tempa[3]);
			}

			tempa[0] = tempa[0] ^ Rcon[i / Nk];
		}
		if (i % Nk == 4)
		{
			// Function Subword()
			{
				tempa[0] = getSBoxValue(tempa[0]);
				tempa[1] = getSBoxValue(tempa[1]);
				tempa[2] = getSBoxValue(tempa[2]);
				tempa[3] = getSBoxValue(tempa[3]);
			}
		}
		j = i * 4; k = (i - Nk) * 4;
		RoundKey[j + 0] = RoundKey[k + 0] ^ tempa[0];
		RoundKey[j + 1] = RoundKey[k + 1] ^ tempa[1];
		RoundKey[j + 2] = RoundKey[k + 2] ^ tempa[2];
		RoundKey[j + 3] = RoundKey[k + 3] ^ tempa[3];
	}
}

void AES_init_ctx_iv(struct AES_ctx* ctx, const uint8_t* key, const uint8_t* iv)
{
	KeyExpansion(ctx->RoundKey, key);
	memcpy(ctx->Iv, iv, BLOCK_SIZE);
}

/* This function adds the round key to state. The round key is added to the state by an XOR function.
* round: state variable containing the round number
* state: state variable containing the current state of pt to ct conversion for this round
* RoundKey: contains the key rounded for the current round
*/
__device__ void AddRoundKey(uint8_t round, state_t* state, const uint8_t* RoundKey)
{
	uint8_t i, j;
	for (i = 0; i < 4; ++i)
	{
		for (j = 0; j < 4; ++j)
		{
			(*state)[i][j] ^= RoundKey[(round * Nb * 4) + (i * Nb) + j];
		}
	}
}

__device__ uint8_t xtime(uint8_t x)
{
	return ((x << 1) ^ (((x >> 7) & 1) * 0x1b));
}

__device__ uint8_t Multiply(uint8_t x, uint8_t y)
{
	return (((y & 1) * x) ^
		((y >> 1 & 1) * xtime(x)) ^
		((y >> 2 & 1) * xtime(xtime(x))) ^
		((y >> 3 & 1) * xtime(xtime(xtime(x)))) ^
		((y >> 4 & 1) * xtime(xtime(xtime(xtime(x)))))); /* this last call to xtime() can be omitted */
}

__device__ uint8_t getSBoxInvert(uint8_t num)
{
	return d_rsbox[num];
}

/** MixColumns function mixes the columns of the state matrix. 
*  state: state variable containing the current state of pt to ct conversion for this round
*/ 
__device__ void InvMixColumns(state_t* state)
{
	int i;
	uint8_t a, b, c, d;
	for (i = 0; i < 4; ++i)
	{
		a = (*state)[i][0];
		b = (*state)[i][1];
		c = (*state)[i][2];
		d = (*state)[i][3];

		(*state)[i][0] = Multiply(a, 0x0e) ^ Multiply(b, 0x0b) ^ Multiply(c, 0x0d) ^ Multiply(d, 0x09);
		(*state)[i][1] = Multiply(a, 0x09) ^ Multiply(b, 0x0e) ^ Multiply(c, 0x0b) ^ Multiply(d, 0x0d);
		(*state)[i][2] = Multiply(a, 0x0d) ^ Multiply(b, 0x09) ^ Multiply(c, 0x0e) ^ Multiply(d, 0x0b);
		(*state)[i][3] = Multiply(a, 0x0b) ^ Multiply(b, 0x0d) ^ Multiply(c, 0x09) ^ Multiply(d, 0x0e);
	}
}

/** The SubBytes Function Substitutes the values in the state matrix with values in an S-box.
* state:  state variable containing the current state of pt to ct conversion for this round
*/
__device__ void InvSubBytes(state_t* state)
{
	uint8_t i, j;
	for (i = 0; i < 4; ++i)
	{
		for (j = 0; j < 4; ++j)
		{
			(*state)[j][i] = getSBoxInvert((*state)[j][i]);
		}
	}
}

/* Reverse of the shift row operation
* state: state variable containing the current state of pt to ct conversion for this round
*/
__device__ void InvShiftRows(state_t* state)
{
	uint8_t temp;

	// Rotate first row 1 columns to right  
	temp = (*state)[3][1];
	(*state)[3][1] = (*state)[2][1];
	(*state)[2][1] = (*state)[1][1];
	(*state)[1][1] = (*state)[0][1];
	(*state)[0][1] = temp;

	// Rotate second row 2 columns to right 
	temp = (*state)[0][2];
	(*state)[0][2] = (*state)[2][2];
	(*state)[2][2] = temp;

	temp = (*state)[1][2];
	(*state)[1][2] = (*state)[3][2];
	(*state)[3][2] = temp;

	// Rotate third row 3 columns to right
	temp = (*state)[0][3];
	(*state)[0][3] = (*state)[1][3];
	(*state)[1][3] = (*state)[2][3];
	(*state)[2][3] = (*state)[3][3];
	(*state)[3][3] = temp;
}

/* implementation of the decryption operation
* state: state variable containing the current state of pt to ct conversion for this round
* RoundKey: rounded key for the round
*/
__device__ void InvCipher(state_t* state, const uint8_t* RoundKey)
{
	uint8_t round = 0;

	// Add the First round key to the state before starting the rounds.
	AddRoundKey(Nr, state, RoundKey);

	// There will be Nr rounds.
	// The first Nr-1 rounds are identical.
	// These Nr rounds are executed in the loop below.
	// Last one without InvMixColumn()
	for (round = (Nr - 1); ; --round)
	{
		InvShiftRows(state);
		InvSubBytes(state);
		AddRoundKey(round, state, RoundKey);
		if (round == 0) {
			break;
		}
		InvMixColumns(state);
	}

}

__global__ void AES_CBC_decrypt_buffer(struct AES_ctx* ctx, unsigned char* ct,unsigned char* pt,size_t length)
{
	size_t i;
	uint8_t storeNextIv[BLOCK_SIZE];
	printf("CIAO\n");
	for (i = 0; i < length; i += BLOCK_SIZE)
	{
		memcpy(storeNextIv, ct, BLOCK_SIZE);
		InvCipher((state_t*)ct, ctx->RoundKey);
		XorWithIv(ct, ctx->Iv);
		memcpy(ctx->Iv, storeNextIv, BLOCK_SIZE);
		ct += BLOCK_SIZE;
		printf("CIAO\n");
	}

	printf("%s\n", ct);
}

/* *************************************************************************************************/
/* ******************************************* UTILITY *********************************************/
/* *************************************************************************************************/

/** Perfrom a read from a file
 * file: name of the file to read
 */
__host__ string read_data_from_file(string file){

	fstream getFile;
	string str;
	string file_contents;
	getFile.open(file,ios::in | ios::binary);

	while (getline(getFile, str)){
		file_contents += str;
		file_contents.push_back('\n');
	} 

	file_contents.pop_back();
	
	getFile.close();
	
	return file_contents;
}

/** Function that perform a conversion from Hexadecimal number into their ASCII representation
 * hex: string that contains the Hexadecimal rapresentation of the text 
 */
__host__ string hexToASCII(string hex){

    // initialize the ASCII code string as empty.
    string ascii = "";
    for (size_t i = 0; i < hex.length(); i += 2)
    {
        // extract two characters from hex string
        string part = hex.substr(i, 2);
 
        // change it into base 16 and
        // typecast as the character
        char ch = stoul(part, nullptr, 16);
        // add this char to final ASCII string
        ascii += ch;
    }
    return ascii;
}

/** Perform a convertion of the key from exadecimal to ASCII and save it on another file
 * file_to_read: file on which we read the exadecimal format key
 * file_to_save: file on which we save the converted key
 */
__host__ void convert_key(string file_to_read, string file_to_save){
	string str = read_data_from_file(file_to_read);
	ofstream SaveFile(file_to_save, ios::out | ios::binary);
	SaveFile << hexToASCII(str);
	SaveFile.close();

}


int main (int argc, char **argv){
	
	/* ------------------------------------- GET KEY -------------------------------------------------------- */
	printf("------------------------------------- GET KEY --------------------------------------------------------\n");
	
	convert_key(iv_file_hex, iv_file);
	convert_key(key_aes_hex_file, key_aes_file);
	unsigned char* iv_aes = (unsigned char*)malloc(IV_KEYLENGTH);
	if(!iv_aes){
		printf ("ERROR: iv space allocation went wrong\n");
		return -1;
	}
	memset(iv_aes, 0, IV_KEYLENGTH);
	strcpy((char*)iv_aes, (char*)read_data_from_file(iv_file).c_str());
	if(DEBUG){
		printf ("IV: %s\n", iv_aes);
	}

	
	unsigned char* key_aes = (unsigned char*)malloc(AES_KEYLENGTH);
	if(!key_aes){
        printf ("ERROR: key space allocation went wrong\n");
		return -1;
	}
	memset(key_aes,0,AES_KEYLENGTH);
	strcpy((char*)key_aes, (char*)read_data_from_file(key_aes_file).c_str());
	if(DEBUG){
        printf ("KEY TO ENCRYPT: %s With length: %lu\n", key_aes, (uint32_t)strlen((char*)key_aes));
	}

    printf("------------------------------------------------------------------------------------------------------\n");
	/* ------------------------------------- GET PT -------------------------------------------------------- */
	printf("------------------------------------- GET PT ---------------------------------------------------------\n");



	//Allocating pt space
	unsigned char* plaintext = (unsigned char*)malloc(PLAINTEXT_LENGHT);
	if(!plaintext){
		printf ("ERROR: plaintext space allocation went wrong\n");
		return -1;
	}
	memset(plaintext,0,PLAINTEXT_LENGHT);
	strcpy((char*)plaintext, (char*)read_data_from_file(plaintext_file).c_str());

	if(DEBUG){
		printf("DEBUG: The Plaintext is: %s\n", plaintext);
	}

	printf("------------------------------------------------------------------------------------------------------\n");
	/* ------------------------------------- GET CT -------------------------------------------------------- */
	printf("------------------------------------- GET CT ---------------------------------------------------------\n");

	//Allocating ct space
	const uint32_t CT_LEN = PLAINTEXT_LENGHT + 3;
	unsigned char* ciphertext = (unsigned char*)malloc(CT_LEN);
	if (!ciphertext) {
		printf("ERROR: CT space allocation went wrong\n");
		return -1;
	}
	memset(ciphertext, 0, CT_LEN);
	strcpy((char*)ciphertext, (char*)read_data_from_file(ciphertext_file).c_str());

	if (DEBUG) {
		printf("DEBUG: The Ciphertext is: %s\n", ciphertext);
	}

	printf("------------------------------------------------------------------------------------------------------\n");
	/* ------------------------------------------ DEC ------------------------------------------------------------ */
	printf("---------------------------------------- DEC ----------------------------------------------------------\n");

	//"d_" variables are the device ones
	struct AES_ctx d_ctx;
	unsigned char* d_key_aes, *d_iv_aes, *d_ciphertext, *d_plaintext;

	//Allocation of variables needed for decryption
	cudaError_t rc = cudaMalloc((void**)&d_ctx,sizeof(AES_ctx));
	if (rc != cudaSuccess) {
		printf("Errore durante allocazione: 1!\n");
		return -1;
	}
	rc = cudaMalloc((void**)&d_key_aes, AES_KEYLENGTH);
	if (rc != cudaSuccess) {
		printf("Errore durante allocazione: 2!\n");
		return -1;
	}
	rc = cudaMalloc((void**)&d_iv_aes, IV_KEYLENGTH);
	if (rc != cudaSuccess) {
		printf("Errore durante allocazione: 3!\n");
		return -1;
	}
	rc = cudaMalloc((void**)&d_plaintext, 445);
	if (rc != cudaSuccess) {
		printf("Errore durante allocazione: 4!\n");
		return -1;
	}
	rc = cudaMalloc((void**)&d_ciphertext, 448);
	if (rc != cudaSuccess) {
		printf("Errore durante allocazione: 5!\n");
		return -1;
	}
	printf("CIAO\n");
	//Copy the variables value on GPU dynamic memory
	cudaMemcpy(d_key_aes, &key_aes, AES_KEYLENGTH, cudaMemcpyHostToDevice);
	cudaMemcpy(d_iv_aes, &iv_aes, IV_KEYLENGTH, cudaMemcpyHostToDevice);
	cudaMemcpy(d_plaintext, &plaintext, 445, cudaMemcpyHostToDevice);
	cudaMemcpy(d_ciphertext, &ciphertext, 448, cudaMemcpyHostToDevice);
	printf("CIAO\n");
	//Set the ciphertext context
	AES_init_ctx_iv(&d_ctx, d_key_aes, (uint8_t*)d_iv_aes);
	printf("CIAO\n");

	AES_CBC_decrypt_buffer<<<1,1>>>(&d_ctx, d_ciphertext, d_plaintext, 448);

	return 0;

}