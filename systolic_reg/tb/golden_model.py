import random

def matrixMultiplier(matA: list, matB: list):
    n = len(matA)
    matAB = [ [0 for _ in range(n)] for _ in range(n) ]

    accumulator = 0
    for i in range(n):
        for j in range(n):
            for k in range(n):
                accumulator += matA[i][k]*matB[k][j]
                if k==n-1:
                    matAB[i][j] = accumulator
                    accumulator = 0 
    return matAB

def generateMatrix(n: int, bitWidth: int):
    return [ [random.randint(0, 2**bitWidth - 1) for _ in range(n)] for _ in range(n) ]

if __name__ == "__main__":
    n = 4
    width = 8

    matA = generateMatrix(n, width)
    matB = generateMatrix(n, width)

    print(f"A = {matA}")
    print(f"B = {matB}")

    matAB = matrixMultiplier(matA, matB)

    print(f"AB = {matAB}")