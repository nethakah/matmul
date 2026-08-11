import random

def matrixMultiplier(matA: list, matB: list):
    m = len(matA)       # rows of A
    n = len(matA[0])    # cols of A = rows of B (contraction)
    k = len(matB[0])    # cols of B
    matAB = [ [0 for _ in range(k)] for _ in range(m) ]

    for i in range(m):
        for j in range(k):
            accumulator = 0
            for p in range(n):
                accumulator += matA[i][p]*matB[p][j]
            matAB[i][j] = accumulator
    return matAB

def generateMatrix(rows: int, cols: int, bitWidth: int):
    return [ [random.randint(0, 2**bitWidth - 1) for _ in range(cols)] for _ in range(rows) ]

if __name__ == "__main__":
    m = 4
    n = 4
    k = 4
    width = 8

    matA = generateMatrix(m, n, width)
    matB = generateMatrix(n, k, width)

    print(f"A = {matA}")
    print(f"B = {matB}")

    matAB = matrixMultiplier(matA, matB)

    print(f"AB = {matAB}")