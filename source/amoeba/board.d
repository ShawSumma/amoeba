/*
 * File board.d
 * Chess board representation, move generation, etc.
 * © 2016-2021 Richard Delorme
 */

module amoeba.board;

import amoeba.move, amoeba.util, amoeba.tt;
import std.algorithm, std.ascii, std.conv, std.format, std.getopt, std.math, std.random, std.range, std.stdio, std.string, std.uni;

/*
 * Color
 */
enum Color : ubyte {white, black, size, none}

// Opponent color
Color opponent(const Color c) {
	return cast (Color) !c;
}

// Conversion from a char
Color toColor(const char c) {
	size_t i = indexOf("wb", c);
	if (i == -1) i = Color.size;
	return cast (Color) i;
}

/*
 * Piece
 */
/* Piece enumeration */
enum Piece : ubyte {none, pawn, knight, bishop, rook, queen, king, size}

/* Convert to a piece from a char */
Piece toPiece(const char c) {
	size_t i = indexOf(".pnbrqk", c, CaseSensitive.no);
	if (i == -1) i = 0;
	return cast (Piece) i;
}

char toChar(const Piece p) {
	return ".PNBRQK#"[p];
}

/*
 * Colored Piece
 */
/* CPiece enumeration */
enum CPiece : ubyte {none, unused, wpawn, bpawn, wknight, bknight, wbishop, bbishop, wrook, brook, wqueen, bqueen, wking, bking, size}

/* Conversion from piece & color */
CPiece toCPiece(const Piece p, const Color c) {
	return cast (CPiece) (2 * p + c);
}

/* Conversion from a char */
CPiece toCPiece(const char c) {
	size_t i = indexOf(".?PpNnBbRrQqKk", c);
	if (i == -1) i = 0;
	return cast (CPiece) i;
}

/* Get the color of a colored piece */
Color toColor(const CPiece p) {
	static immutable Color[CPiece.size] c= [Color.none, Color.none,
		Color.white, Color.black, Color.white, Color.black, Color.white, Color.black,
		Color.white, Color.black, Color.white, Color.black, Color.white, Color.black];
	return c[p];
}

/* Get the piece of a colored piece */
Piece toPiece(const CPiece p) {
	return cast (Piece) (p >> 1);
}

/* Get the opponent colored piece */
CPiece opponent(const CPiece p) {
	return cast (CPiece) (p ^ 1);
}

/* get a char from a CPiece */
char toChar(const CPiece p) {
	return ".?PpNnBbRrQqKk#"[p];
}

/*
 * Square
 */
/* Square enumeration */
enum Square : ubyte {
	a1, b1, c1, d1, e1, f1, g1, h1,
	a2, b2, c2, d2, e2, f2, g2, h2,
	a3, b3, c3, d3, e3, f3, g3, h3,
	a4, b4, c4, d4, e4, f4, g4, h4,
	a5, b5, c5, d5, e5, f5, g5, h5,
	a6, b6, c6, d6, e6, f6, g6, h6,
	a7, b7, c7, d7, e7, f7, g7, h7,
	a8, b8, c8, d8, e8, f8, g8, h8,
	size, none
}

/* an array with all the squares */
auto allSquares() {
	return iota(Square.a1, Square.size).array;
}

/* return the square + δ */
Square shift(const Square x, const int δ) {
	return cast (Square) (x + δ);
}

/* return the captured enpassant square */
Square enpassant(const Square x) {
	return cast (Square) (x ^ 8);
}

/* Mirror square */
Square mirror(const Square x) {
	return cast (Square) (x ^ 56);
}

/* Mirror square for black */
Square forward(const Square x, const Color c) {
	return cast (Square) (x ^ (56 * c));
}

/* Get rank */
int rank(const Square x) {
	return x >> 3;
}

/* Get file */
int file(const Square x) {
	return x & 7;
}

/* Square from file & rank */
Square toSquare(const int f, const int r) {
	if (0 <= f && f < 8 && 0 <= r && r < 8) return cast (Square) ((r << 3) + f);
	else return Square.none;
}

/* Square from string */
Square toSquare(string s) {
	if (s.length > 1) return toSquare(s[0] - 'a', s[1] - '1');
	else return Square.none;

}

/* Get the first square from a bitboard and remove it from the bitboard */
Square popSquare(ref ulong b) {
	return cast (Square) popBit(b);
}

/* Get the last square from a bitboard and remove it from the bitboard */
Square reversePopSquare(ref ulong b) {
	return cast (Square) reversePopBit(b);
}

/* Get the first square from a bitboard */
Square firstSquare(const ulong b) {
	return cast (Square) firstBit(b);
}

/* Square to bit */
ulong toBit(const Square x) {
	return 1UL << x;
}

/*
 * Miscs
 */

/* File mask */
enum File {
	A = 0x0101010101010101,
	B = 0x0202020202020202,
	C = 0x0404040404040404,
	D = 0x0808080808080808,
	E = 0x1010101010101010,
	F = 0x2020202020202020,
	G = 0x4040404040404040,
	H = 0x8080808080808080
}

/* Rank mask */
enum Rank {
	r1 = 0x00000000000000ffUL,
	r2 = 0x000000000000ff00UL,
	r3 = 0x0000000000ff0000UL,
	r4 = 0x00000000ff000000UL,
	r5 = 0x000000ff00000000UL,
	r6 = 0x0000ff0000000000UL,
	r7 = 0x00ff000000000000UL,
	r8 = 0xff00000000000000UL
}

/* Castling */
enum Castling : ubyte {none = 0, K = 1, Q = 2, k = 4, q = 8, size = 16}

int toCastling(const char c) {
	size_t i = indexOf("KQkq", c);
	if (i == -1) return 0;
	else return 1 << i;
}

/*
 * Zobrist key
 */
struct Key {
	ulong zobrist;

	static immutable ulong [Square.size][CPiece.size] square;
	static immutable ulong [Castling.size] castling;
	static immutable ulong [Square.none + 1] enpassant;
	static immutable ulong [Color.size] color;
	static immutable ulong play;

	/* initialize Zobrist keys with pseudo random numbers */
	shared static this() {
		Mt19937 r;
		r.seed(19_937);
		foreach (p; CPiece.wpawn .. CPiece.size)
		foreach (x; Square.a1 .. Square.size) square[p][x] = uniform(ulong.min, ulong.max, r);
		foreach (c; Castling.K .. Castling.size) castling[c] = uniform(ulong.min, ulong.max, r);
		foreach (x; Square.a3 .. Square.a4) enpassant[x] = uniform(ulong.min, ulong.max, r);
		foreach (x; Square.a6 .. Square.a7) enpassant[x] = uniform(ulong.min, ulong.max, r);
		foreach (c; Color.white .. Color.size) color[c] = uniform(ulong.min, ulong.max, r);
		play = color[Color.white] ^ color[Color.black];
	}

	/* set the key from a position */
	void set(const Board board) {
		const Board.Stack *s = &board.stack[board.ply];
		zobrist = color[board.player];
		foreach (Square x; Square.a1 .. Square.size) zobrist ^= square[board[x]][x];
		zobrist ^= enpassant[s.enpassant];
		zobrist ^= castling[s.castling];
	}

	/* update the key with a move */
	void update(const Board board, Move move) {
		Square x = Square.none;
		const Color player = board.player;
		const Color enemy = opponent(player);
		const CPiece p = board[move.from];
		const Board.Stack *s = &board.stack[board.ply];

		zobrist = s.key.zobrist;
		zobrist ^= play;
		if (move != 0) {
			zobrist ^= square[p][move.from] ^ square[p][move.to];
			zobrist ^= square[board[move.to]][move.to];
			if (toPiece(p) == Piece.pawn) {
				if (move.promotion) zobrist ^= square[p][move.to] ^ square[toCPiece(move.promotion, player)][move.to];
				else if (s.enpassant == move.to) zobrist ^= square[toCPiece(Piece.pawn, enemy)][move.to.enpassant];
				else if (abs(move.to - move.from) == 16 && (board.mask[move.to].enpassant & (board.color[enemy] & board.piece[Piece.pawn]))) {
					x = cast (Square) ((move.from + move.to) / 2);
				}
			} else if (toPiece(p) == Piece.king) {
				CPiece r = toCPiece(Piece.rook, board.player);
				if (move.to == move.from + 2) zobrist ^= square[r][move.from + 3] ^ square[r][move.from + 1];
				else if (move.to == move.from - 2) zobrist ^= square[r][move.from - 4] ^ square[r][move.from - 1];
			}
			zobrist ^= enpassant[s.enpassant] ^ enpassant[x];
			zobrist ^= castling[s.castling] ^ castling[s.castling & board.mask[move.from].castling & board.mask[move.to].castling];
		}
	}

	/* index */
	size_t index(const size_t mask) const {
		return cast (size_t) (zobrist & mask);
	}

	/* code */
	uint code() const @property {
		return cast (uint) (zobrist >> 32);
	}

	/* create a key from the current positional key with a move excluded */
	Key exclude(const Move m) const {
		Key k;
		k.zobrist = zobrist ^ (m * 2862933555777941757);
		return k;
	}
}


/*
 * Zobrist pawn key
 */
struct PawnKey {
	ulong zobrist;

	/* set the key from a position */
	void set(const Board board) {
		ulong b = board.piece[Piece.pawn] | board.piece[Piece.king];
		zobrist = 0;
		while (b) {
			auto x = popSquare(b);
			zobrist ^= Key.square[board[x]][x];
		}
	}

	/* update the key with a move */
	void update(const Board board, Move move) {
		const CPiece p = board[move.from];
		const Board.Stack *s = &board.stack[board.ply];

		zobrist = s.pawnKey.zobrist;
		if (toPiece(p) == Piece.pawn) {
			zobrist ^= Key.square[p][move.from];
			if (!move.promotion) zobrist ^= Key.square[p][move.to];
			if (s.enpassant == move.to) zobrist ^= Key.square[opponent(p)][move.to.enpassant];
		} else if (toPiece(p) == Piece.king) {
			zobrist ^= Key.square[p][move.from] ^ Key.square[p][move.to];
		}
		if (toPiece(board[move.to]) == Piece.pawn) zobrist ^= Key.square[board[move.to]][move.to];
	}

	/* index */
	size_t index(const size_t mask) const {
		return cast (size_t) (zobrist & mask);
	}

	/* code */
	uint code() const @property {
		return cast (uint) (zobrist >> 32);
	}

}

/*
 * Bitmask
 */
struct Mask {
	ulong diagonal;                      // diagonal thru square x
	ulong antidiagonal;                  // antidiagonal thru square x
	ulong file;                          // file thru square x
	ulong [Color.size] pawnAttack;       // pawn attack from x
	ulong [Color.size] pawnPush;         // pawn push from x
	ulong [Color.size] openFile;         // open file from x
	ulong [Color.size] passedPawn;       // passed pawn from x
	ulong [Color.size] backwardPawn;     // backward pawn from x
	ulong isolatedPawn;                  // isolated pawn from x
	ulong enpassant;                     // enpassant
	ulong knight;                        // knight moves from x
	ulong king;                          // king moves from x
	ulong [Square.size] between;         // squares between x & y
	ubyte [Square.size] direction;       // direction between x & y
	ubyte castling;                      // castling right
}

/* Kind of move Generation */
enum Generate {all, capture, quiet}

/*
 * Class board
 */
final class Board {

public:
	struct Stack {
		ulong pins;
		ulong checkers;
		Key key;
		PawnKey pawnKey;
		Square enpassant = Square.none;
		Piece victim;
		byte fifty;
		Castling castling;
	}
	ulong [Piece.size] piece;
	ulong [Color.size] color;
	CPiece [Square.size] cpiece;
	Stack [Limits.game.size] stack;
	Square [Color.size] xKing;
	Color player;
	int ply, plyOffset;

	static immutable Mask [Square.size] mask;
	enum { whiteSquares = 0xaa55aa55aa55aa55, blackSquares = 0x55aa55aa55aa55aa }
private:
	static immutable bool [Limits.move.size][Piece.size] legal;
	static immutable ubyte [512] ranks;
	static immutable Castling [Color.size] kingside = [Castling.K, Castling.k];
	static immutable Castling [Color.size] queenside = [Castling.Q, Castling.q];
	static immutable int [Piece.size] seeValue = [0, 1, 3, 3, 5, 9, 300];

	/* constant initialisation at compile time */
	shared static this() {
		// mask
		int r, f, i, j, y, z, b;
		byte [Square.size][Square.size] d;
		immutable ubyte [6] castling = [13, 12, 14, 7, 3, 11];
		immutable Square [6] castlingX = [Square.a1, Square.e1, Square.h1, Square.a8, Square.e8, Square.h8];

		foreach (x; Square.a1 .. Square.size) {
			int c;

			for (i = -1; i <= 1; ++i)
			for (j = -1; j <= 1; ++j) {
				if (i == 0 && j == 0) continue;
				f = x & 07;
				r = x >> 3;
				for (r += i, f += j; 0 <= r && r < 8 && 0 <= f && f < 8; r += i, f += j) {
			 		y = 8 * r + f;
					d[x][y] = cast (byte) (8 * i + j);
					mask[x].direction[y] = abs(d[x][y]);
			 	}
			}

			for (y = 0; y < Square.size; ++y) {
				i = d[x][y];
				if (i) {
					for (z = x + i; z != y; z += i) mask[x].between[y] |= 1UL << z;
				}
			}

			for (y = x - 9; y >= 0 && d[x][y] == -9; y -= 9) mask[x].diagonal |= 1UL << y;
			for (y = x + 9; y < Square.size && d[x][y] == 9; y += 9) mask[x].diagonal |= 1UL << y;

			for (y = x - 7; y >= 0 && d[x][y] == -7; y -= 7) mask[x].antidiagonal |= 1UL << y;
			for (y = x + 7; y < Square.size && d[x][y] == 7; y += 7) mask[x].antidiagonal |= 1UL << y;

			for (y = x - 8; y >= 0; y -= 8) mask[x].file |= 1UL << y;
			for (y = x + 8; y < Square.size; y += 8) mask[x].file |= 1UL << y;

			f = x & 07;
			r = x >> 3;
			for (i = -1, c = 1; i <= 1; i += 2, c = 0) {
				for (j = -1; j <= 1; j += 2) {
					if (0 <= r + i && r + i < 8 && 0 <= f + j && f + j < 8) {
						 y = (r + i) * 8 + (f + j);
						 mask[x].pawnAttack[c] |= 1UL << y;
					}
				}
				if (0 <= r + i && r + i < 8) {
					y = (r + i) * 8 + f;
					mask[x].pawnPush[c] = 1UL << y;
				}
			}
			for (i = -1, c = 1; i <= 1; i += 2, c = 0) {
				for (y = 8 * (r + i) + f; 8 <= y && y < 56 ; y += i * 8) {
					mask[x].openFile[c] |= 1UL << y;
					if (f > 0) mask[x].passedPawn[c] |= 1UL << (y - 1);
					if (f < 7) mask[x].passedPawn[c] |= 1UL << (y + 1);
				}
				for (y = 8 * (r - i) + f; 8 <= y && y < 56 ; y -= i * 8) {
					if (f > 0) mask[x].backwardPawn[c] |= 1UL << (y - 1);
					if (f < 7) mask[x].backwardPawn[c] |= 1UL << (y + 1);
				}
			}
			if (f > 0) {
				for (y = x - 1; y < 56; y += 8) mask[x].isolatedPawn |= 1UL << y;
				for (y = x - 9; y >= 8; y -= 8) mask[x].isolatedPawn |= 1UL << y;
			}
			if (f < 7) {
				for (y = x + 1; y < 56; y += 8) mask[x].isolatedPawn |= 1UL << y;
				for (y = x - 7; y >= 8; y -= 8) mask[x].isolatedPawn |= 1UL << y;
			}
			if (r == 3 || r == 4) {
				if (f > 0) mask[x].enpassant |=  1UL << x - 1;
				if (f < 7) mask[x].enpassant |=  1UL << x + 1;
			}

			for (i = -2; i <= 2; i = (i == -1 ? 1 : i + 1))
			for (j = -2; j <= 2; ++j) {
				if (i == j || i == -j || j == 0) continue;
				if (0 <= r + i && r + i < 8 && 0 <= f + j && f + j < 8) {
			 		y = 8 * (r + i) + (f + j);
			 		mask[x].knight |= 1UL << y;
				}
			}

			for (i = -1; i <= 1; ++i)
			for (j = -1; j <= 1; ++j) {
				if (i == 0 && j == 0) continue;
				if (0 <= r + i && r + i < 8 && 0 <= f + j && f + j < 8) {
			 		y = 8 * (r + i) + (f + j);
			 		mask[x].king |= 1UL << y;
				}
			}
			mask[x].castling = 15;
		}

		foreach (k; 0 .. 6) mask[castlingX[k]].castling = castling[k];

		// ranks
		foreach (o; 0 .. 64) {
			foreach (k; 0 .. 8) {
				y = 0;
				foreach_reverse (x; 0 .. k) {
					b = 1 << x;
					y |= b;
					if (((o << 1) & b) == b) break;
				}
				foreach (x; k + 1 .. 8) {
					b = 1 << x;
					y |= b;
					if (((o << 1) & b) == b) break;
				}
				ranks[o * 8 + k] = cast (ubyte) y;
			}
		}

		// legal
		foreach (x; Square.a2 .. Square.a8) {
			legal[Piece.pawn][toMove(x, x + 8)] = true;
			if (rank(x) == 1) legal[Piece.pawn][toMove(x, x + 16)] = true;
			if (file(x) < 7) legal[Piece.pawn][toMove(x, x + 9)] = true;
			if (file(x) > 0) legal[Piece.pawn][toMove(x, x + 7)] = true;
		}

		foreach (x; Square.a1 .. Square.size) {
			f = file(x), r = rank(x);

			foreach (c; Color.white .. Color.size) {
				for (i = -2; i <= 2; ++i)
				for (j = -2; j <= 2; ++j) {
					if (i == 0 || i == j || i == -j || j == 0) continue;
					if (0 <= r + i && r + i < 8 && 0 <= f + j && f + j < 8) legal[Piece.knight][toMove(x, toSquare(f + j, r + i))] = true;
				}

				for (i = f - 1, j = r - 1; i >= 0 && j >= 0; --i, --j) legal[Piece.bishop][toMove(x, toSquare(i, j))] = true;
				for (i = f + 1, j = r - 1; i <= 7 && j >= 0; ++i, --j) legal[Piece.bishop][toMove(x, toSquare(i, j))] = true;
				for (i = f - 1, j = r + 1; i >= 0 && j <= 7; --i, ++j) legal[Piece.bishop][toMove(x, toSquare(i, j))] = true;
				for (i = f + 1, j = r + 1; i <= 7 && j <= 7; ++i, ++j) legal[Piece.bishop][toMove(x, toSquare(i, j))] = true;

				for (i = f - 1; i >= 0; --i) legal[Piece.rook][toMove(x, toSquare(i, r))] = true;
				for (i = f + 1; i <= 7; ++i) legal[Piece.rook][toMove(x, toSquare(i, r))] = true;
				for (j = r - 1; j >= 0; --j) legal[Piece.rook][toMove(x, toSquare(f, j))] = true;
				for (j = r + 1; j <= 7; ++j) legal[Piece.rook][toMove(x, toSquare(f, j))] = true;

				for (i = f - 1, j = r - 1; i >= 0 && j >= 0; --i, --j) legal[Piece.queen][toMove(x, toSquare(i, j))] = true;
				for (i = f + 1, j = r - 1; i <= 7 && j >= 0; ++i, --j) legal[Piece.queen][toMove(x, toSquare(i, j))] = true;
				for (i = f - 1, j = r + 1; i >= 0 && j <= 7; --i, ++j) legal[Piece.queen][toMove(x, toSquare(i, j))] = true;
				for (i = f + 1, j = r + 1; i <= 7 && j <= 7; ++i, ++j) legal[Piece.queen][toMove(x, toSquare(i, j))] = true;
				for (i = f - 1; i >= 0; --i) legal[Piece.queen][toMove(x, toSquare(i, r))] = true;
				for (i = f + 1; i <= 7; ++i) legal[Piece.queen][toMove(x, toSquare(i, r))] = true;
				for (j = r - 1; j >= 0; --j) legal[Piece.queen][toMove(x, toSquare(f, j))] = true;
				for (j = r + 1; j <= 7; ++j) legal[Piece.queen][toMove(x, toSquare(f, j))] = true;


				for (i = f - 1; i <= f + 1; ++i)
				for (j = r - 1; j <= r + 1; ++j)
					if (0 <= i && i <= 7 && 0 <= j && j <= 7 && toSquare(i, j) != x) legal[Piece.king][toMove(x, toSquare(i, j))] = true;
			}
			legal[Piece.king][toMove(Square.e1, Square.g1)] = true;
			legal[Piece.king][toMove(Square.e1, Square.c1)] = true;
		}
	}

	bool canCastle(const Castling side, const int k, const int r, const ulong occupancy) const {
		const Color enemy = opponent(player);
		if ((stack[ply].castling & side) == 0 || (occupancy & mask[k].between[r]) != 0) return false;
		foreach (x ; (k > r ? k - 2 : k + 1) .. (k > r ? k : k + 3))  if (isSquareAttacked(cast (Square) x, enemy, color[enemy], occupancy)) return false;
		return true;
	}

	/* slider attack function for the file, diagonal & antidiagonal directions */
	static ulong attack(const ulong occupancy, const Square x, const ulong m)  {
		const ulong o = occupancy & m;
		const ulong r = swapBytes(o);
		return ((o - x.toBit) ^ swapBytes(r - x.mirror.toBit)) & m;
	}

	/* Deplace a piece on the board */
	void deplace(const Square from, const Square to, const Piece p) {
		const ulong M = from.toBit ^ to.toBit;
		piece[Piece.none] ^= M;
		piece[p] ^= M;
		color[player] ^= M;
		cpiece[to] = cpiece[from];
		cpiece[from] = CPiece.none;
	}

	void capture(const Piece victim, const Square x, const Color enemy) {
		const ulong M = x.toBit;
		piece[Piece.none] ^= M;
		piece[victim] ^= M;
		color[enemy] ^= M;
	}


	/* check if a square is attacked */
	bool isSquareAttacked(const Square x, const Color player, const ulong P, const ulong occupancy) const {
		return attack(Piece.bishop, x, P & (piece[Piece.bishop] | piece[Piece.queen]), occupancy)
			|| attack(Piece.rook, x, P & (piece[Piece.rook] | piece[Piece.queen]), occupancy)
			|| attack(Piece.knight, x, P & piece[Piece.knight])
			|| attack(Piece.pawn, x, P & piece[Piece.pawn], occupancy, opponent(player))
			|| attack(Piece.king, x, P & piece[Piece.king]);
	}

	/* check if a square is attacked */
	bool isSquareAttacked(const Square x, const Color player) const {
		return isSquareAttacked(x, player, color[player], ~piece[Piece.none]);
	}

	/* generate all moves from a square */
	static void generateMoves(ref Moves moves, ulong attack, const Square from) {
		while (attack) {
			Square to = popSquare(attack);
			moves.push(from, to);
		}
	}

	/* generate promotion */
	static void generatePromotions(ref Moves moves, ulong attack, const int dir) {
		while (attack) {
			Square to = popSquare(attack);
			Square from = cast (Square) (to - dir);
			moves.pushPromotions(from, to);
		}
	}

	/* generate pawn moves */
	static void generatePawnMoves (ref Moves moves, ulong attack, const int dir) {
		while (attack) {
			Square to = popSquare(attack);
			Square from = cast (Square) (to - dir);
			moves.push(from, to);
		}
	}

	/* generate all white pawn moves */
	void generateWhitePawnMoves(Generate type) (ref Moves moves, const ulong attacker, const ulong enemies, const ulong empties) const {
		ulong attack;

		static if (type != Generate.quiet) {
			attack = ((attacker & ~File.A) << 7) & enemies;
			generatePromotions(moves, attack & Rank.r8, 7);
			generatePawnMoves(moves, attack & ~Rank.r8, 7);
			attack = ((attacker & ~File.H) << 9) & enemies;
			generatePromotions(moves, attack & Rank.r8, 9);
			generatePawnMoves(moves, attack & ~Rank.r8, 9);
		}
		attack = attacker << 8 & piece[Piece.none];
		static if (type != Generate.quiet) {
			generatePromotions(moves, attack & Rank.r8 & empties, 8);
			generatePawnMoves(moves, attack & Rank.r7 & empties, 8);
		}
		static if (type != Generate.capture) {
			generatePawnMoves(moves, attack & ~(Rank.r8 | Rank.r7) & empties, 8);
			attack = ((attack & Rank.r3) << 8) & empties;
			generatePawnMoves(moves, attack, 16);
		}
	}

	/* generate all black pawn moves */
	void generateBlackPawnMoves(Generate type) (ref Moves moves, const ulong attacker, const ulong enemies, const ulong empties) const {
		ulong attack;

		static if (type != Generate.quiet) {
			attack = ((attacker & ~File.A) >> 9) & enemies;
			generatePromotions(moves, attack & Rank.r1, -9);
			generatePawnMoves(moves, attack & ~Rank.r1, -9);
			attack = ((attacker & ~File.H) >> 7) & enemies;
			generatePromotions(moves, attack & Rank.r1, -7);
			generatePawnMoves(moves, attack & ~Rank.r1, -7);
		}
		attack = (attacker >> 8) & piece[Piece.none];
		static if (type != Generate.quiet) {
			generatePromotions(moves, attack & Rank.r1 & empties, -8);
			generatePawnMoves(moves, attack & Rank.r2 & empties, -8);
		}
		static if (type != Generate.capture) {
			generatePawnMoves(moves, attack & ~(Rank.r1 | Rank.r2) & empties, -8);
			attack = ((attack & Rank.r6) >> 8) & empties;
			generatePawnMoves(moves, attack, -16);
		}
	}

public:
	/* slider attack function along a rank */
	static ulong rankAttack(const ulong occupancy, const Square x) {
		const int f = x & 7;
		const int r = x & 56;
		const int o = (occupancy >> r) & 126;
		return (cast (ulong) (ranks[o * 4  + f])) << r;
	}

	/* Slider attack along a file */
	static ulong fileAttack(const ulong occupancy, const Square x) {
		return attack(occupancy, x, mask[x].file);
	}

	/* Slider attack along a diagonal */
	static ulong diagonalAttack(const ulong occupancy, const Square x) {
		return attack(occupancy, x, mask[x].diagonal);
	}

	/* Slider attack along an antidiagonal */
	static ulong antidiagonalAttack(const ulong occupancy, const Square x) {
		return attack(occupancy, x, mask[x].antidiagonal);
	}

	/* Coverage by a piece */
	static ulong coverage(Piece p, const Square x, const ulong occupancy = 0, const Color c = Color.white) {
		final switch(p) {
			case Piece.pawn:   return mask[x].pawnAttack[c];
			case Piece.knight: return mask[x].knight;
			case Piece.bishop: return diagonalAttack(occupancy, x) + antidiagonalAttack(occupancy, x);
			case Piece.rook:   return fileAttack(occupancy, x) + rankAttack(occupancy, x);
			case Piece.queen:  return diagonalAttack(occupancy, x) + antidiagonalAttack(occupancy, x) + fileAttack(occupancy, x) + rankAttack(occupancy, x);
			case Piece.king:   return mask[x].king;
			case Piece.none, Piece.size: return 0;
		}
	}

	/* Coverage by a piece */
	static ulong attack(Piece p, const Square x, const ulong target, const ulong occupancy = 0, const Color c = Color.white) {
		return coverage(p, x, occupancy, c) & target;
	}

	void clear() {
		foreach (p; Piece.none .. Piece.size) piece[p] = 0;
		foreach (c; Color.white .. Color.size) color[c] = 0;
		foreach (x; Square.a1 .. Square.size) cpiece[x] = CPiece.none;
		stack[0] = Stack.init;
		xKing[0] = xKing[1] = Square.none;
		player = Color.white;
		ply = 0;
	}

	/* set the board from a FEN string */
	Board set(string fen = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1") {
		Square x;
		CPiece p;
		int r = 7, f;
		size_t k, l;
		string [] s = fen.split();

		Board error(string msg) {
			stderr.writeln("error Bad FEN! ", msg, ":\n", fen);
			foreach (i; 0 .. l) stderr.write("-");
			stderr.writeln('^');
			return set();
		}

		clear();

		if (s.length < 4) return error("missing fields");

		k = l = 0;
		foreach (c; s[k]) {
			if (c== '/') {
				if (r <= 0) return error("rank overflow");
				if (f < 8) return error("missing square");
				else if (f > 8) return error("file overflow");
				f = 0; --r;
			} else if (isDigit(c)) {
				f += c - '0';
				if (f > 8) return error("file overflow");
			} else {
				if (f >= 8) return error("file overflow");
				x = toSquare(f, r);
				cpiece[x] = p = toCPiece(c);
				if (cpiece[x] == CPiece.none) return error("bad piece");
				piece[toPiece(p)] |= x.toBit;
				color[toColor(p)] |= x.toBit;
				if (toPiece(p) == Piece.king) xKing[toColor(p)] = x;
				++f;
			}
			++l;
		}
		if (r > 0 || f < 8) return error("missing squares");

		l = s[k].length + 1; k++;
		player = toColor(s[k][0]);
		if (player == Color.size) return error("bad player's turn");

		l += s[k].length + 1; k++;
		if (s[k] != "-") {
			foreach (c; s[k]) stack[ply].castling |= toCastling(c);
		}
		if (cpiece[Square.e1] == CPiece.wking) {
			if (cpiece[Square.h1] != CPiece.wrook) stack[ply].castling &= ~1;
			if (cpiece[Square.a1] != CPiece.wrook) stack[ply].castling &= ~2;
		} else stack[ply].castling &= ~3;
		if (cpiece[Square.e8] == CPiece.bking) {
			if (cpiece[Square.h8] != CPiece.brook) stack[ply].castling &= ~4;
			if (cpiece[Square.a8] != CPiece.brook) stack[ply].castling &= ~8;
		} else stack[ply].castling &= ~12;

		l += s[k].length + 1; k++;
		if (s[k][0] != '-') {
			stack[ply].enpassant = toSquare(s[3]);
			if (stack[ply].enpassant == Square.none) return error("bad enpassant");
		}

		if (s.length > k) {
			try {
				l += s[k].length + 1; k++;
				if (s.length > k && isNumeric(s[k])) stack[ply].fifty = std.conv.to!ubyte(s[4]);
			} catch (Exception e) {
				return error("bad fifty number");
			}

			if (s.length > k) {
				try {
					l += s[k].length + 1; k++;
					if (s.length > k && isNumeric(s[k])) plyOffset = 2 * (std.conv.to!int(s[5]) - 1) + player;
				} catch (Exception e) {
					return error("bad ply number");
				}
			}
		}

		piece[Piece.none] = ~(color[Color.white] | color[Color.black]);
		setPinsCheckers(stack[ply].checkers, stack[ply].pins);
		stack[ply].key.set(this);
		stack[ply].pawnKey.set(this);

		return this;
	}

	/* constructor */
	this() {
		set();
	}

	/* copy constructor */
	this (const Board b) {
		foreach (p; Piece.none .. Piece.size) piece[p] = b.piece[p];
		foreach (c; Color.white .. Color.size) color[c] = b.color[c];
		foreach (x; Square.a1 .. Square.size) cpiece[x] = b.cpiece[x];
		foreach (i; 0 .. cast (int) Limits.game.size) stack[i] = b.stack[i];
		foreach (c; Color.white .. Color.size) xKing[c] = b.xKing[c];

		player = b.player;
		ply = b.ply; plyOffset = b.plyOffset;
	}

	/* duplicate the board */
	Board dup() const @property {
		return new Board(this);
	}

	/* Convert to a printable string */
	override string toString() const {
		Square x;
		int f, r;
		const wchar[] p = ['.', '?', '♙', '♟', '♘' , '♞', '♗', '♝', '♖', '♜', '♕', '♛', '♔', '♚', '#'];
/+		string p = ".PpNnBbRrQqKk#"; +/
		string c = "wb", s;

		s ~= "  a b c d e f g h\n";
		for (r = 7; r >= 0; --r)
		for (f = 0; f <= 7; ++f) {
			x = toSquare(f, r);
			if (f == 0) s ~= format("%1d ", r + 1);
			s ~= p[cpiece[x]];
			s ~= " ";
			if (f == 7) s ~= format("%1d\n", r + 1);
		}
		s ~= "  a b c d e f g h\n";
		s ~= c[player] ~ " ";
		if (stack[ply].castling & Castling.K) s ~= "K";
		if (stack[ply].castling & Castling.Q) s ~= "Q";
		if (stack[ply].castling & Castling.k) s ~= "k";
		if (stack[ply].castling & Castling.q) s ~= "q";
		if (stack[ply].enpassant != Square.none) s ~= format(" ep: %s", stack[ply].enpassant);
		s ~= format(" move %d, fifty %d [K:%s, k:%s]\n", (ply + plyOffset) / 2 + 1, stack[ply].fifty, xKing[Color.white], xKing[Color.black]);

		return s;
	}

	/* convert to a fen string */
	string toFen(LongFormat lf = LongFormat.on)() const {
		Square x;
		int f, r, e, l;
		string p = ".?PpNnBbRrQqKk#", c = "wb", n = "012345678", s;

		l = 0;
		for (r = 7; r >= 0; --r) {
			e = 0;
			for (f = 0; f <= 7; ++f) {
				x = toSquare(f, r);
				if (cpiece[x] == CPiece.none) ++e;
				else {
					if (e) s ~= n[e];
					s ~= p[cpiece[x]];
					e = 0;
				}
			}
			if (e) s ~= n[e];
			if (r > 0) s ~= "/";
		}
		s ~= " " ~ c[player] ~ " ";
		if (stack[ply].castling & Castling.K) s ~= "K";
		if (stack[ply].castling & Castling.Q) s ~= "Q";
		if (stack[ply].castling & Castling.k) s ~= "k";
		if (stack[ply].castling & Castling.q) s ~= "q";
		if (!stack[ply].castling) s ~= "-";
		if (stack[ply].enpassant != Square.none) s ~= format(" %s ", stack[ply].enpassant);
		else s ~= " - ";
		if (lf == LongFormat.on) s ~= format("%d %d", stack[ply].fifty, (ply + plyOffset) / 2 + 1);

		return s;
	}

	/* chess  board content */
	ref CPiece opIndex(const Square x) {
		 return cpiece[x];
	}

	/* chess  board content */
	CPiece opIndex(const Square x) const {
		 return cpiece[x];
	}

	/* king is in check */
	bool inCheck() const @property {
		 return stack[ply].checkers > 0;
	}

	/* precomputed pins for player to move */
	ulong pins() const {
		 return stack[ply].pins;
	}

	/* get pins for a player */
	ulong pins(const Color c) const {
		const Color enemy = opponent(c);
		const Square k = xKing[c];
		const ulong bq = (piece[Piece.bishop] + piece[Piece.queen]) & color[enemy];
		const ulong rq = (piece[Piece.rook] + piece[Piece.queen]) & color[enemy];
		const ulong occupancy = ~piece[Piece.none];
		ulong partialCheckers, pins;
		ulong b;
		Square x;

		// bishop or queen
		b = coverage(Piece.bishop, k, occupancy);
		partialCheckers = b & bq;
		b &= color[c];
		if (b) {
			b = attack(Piece.bishop, k, bq ^ partialCheckers, occupancy ^ b);
			while (b) {
				x = popSquare(b);
				pins |= mask[k].between[x] & color[c];
			}
		}

		// rook or queen: all square reachable from the king square.
		b = coverage(Piece.rook, k, occupancy);
		partialCheckers = b & rq;
		b &= color[c];
		if (b) {
			b = attack(Piece.rook, k, rq ^ partialCheckers, occupancy ^ b);
			while (b) {
				x = popSquare(b);
				pins |= mask[k].between[x] & color[c];
			}
		}

		return pins;
	}

	/* Compute pins & checkers */
	void setPinsCheckers(ref ulong checkers, ref ulong pins) const {
		const Color enemy = opponent(player);
		const Square k = xKing[player];
		const ulong bq = (piece[Piece.bishop] + piece[Piece.queen]) & color[enemy];
		const ulong rq = (piece[Piece.rook] + piece[Piece.queen]) & color[enemy];
		const ulong occupancy = ~piece[Piece.none];
		ulong partialCheckers;
		ulong b;
		Square x;

		pins = checkers = 0;
		// bishop or queen
		if (bq) {
			b = coverage(Piece.bishop, k, occupancy);
			checkers |= partialCheckers = b & bq;
			b &= color[player];
			if (b) {
				b = attack(Piece.bishop, k, bq ^ partialCheckers, occupancy ^ b);
				while (b) {
					x = popSquare(b);
					pins |= mask[k].between[x] & color[player];
				}
			}
		}

		// rook or queen: all square reachable from the king square.
		if (rq) {
			b = coverage(Piece.rook, k, occupancy);
			checkers |= partialCheckers = b & rq;
			b &= color[player];
			if (b) {
				b = attack(Piece.rook, k, rq ^ partialCheckers, occupancy ^ b);
				while (b) {
					x = popSquare(b);
					pins |= mask[k].between[x] & color[player];
				}
			}
		}
		// other occupancy (no more pins)
		checkers |= attack(Piece.knight, k, piece[Piece.knight]);
		checkers |= attack(Piece.pawn, k, piece[Piece.pawn], occupancy, player);
		checkers &= color[enemy];
	}

	/* 50-move rule counter */
	int fifty() const @property {
		 return stack[ply].fifty;
	}

	/* non pawn pieces */
	ulong nonPawnPiece() const {
		return (~piece[Piece.none] ^ piece[Piece.pawn] ^ piece[Piece.king]);
	}

	/* non pawn pieces */
	ulong nonPawnPiece(const Color c) const {
		return (color[c] & ~(piece[Piece.pawn] | piece[Piece.king]));
	}

	/* zobrist key */
	Key key() const @property {
		 return stack[ply].key;
	}

	/* zobrist pawn key */
	PawnKey pawnKey() const @property {
		 return stack[ply].pawnKey;
	}

	/* return true if a position is a draw */
	bool isDraw() const  @property {
		// repetition
		int nRepetition = 0;
		const end = max(0, ply - stack[ply].fifty);
		for (int i = ply - 4; i >= end; i -= 2) {
			if (stack[i].key.code == stack[ply].key.code && ++nRepetition >= 2) return true;
		}

		// fifty move rule
		if (stack[ply].fifty >= 100) return true; // TODO: correct rule: 100 if not mating

		// lack of mating material
		if (piece[Piece.pawn] + piece[Piece.rook] + piece[Piece.queen] == 0) {
			// a single minor: KNK or KBK
			const nMinor = countBits(piece[Piece.knight] + piece[Piece.bishop]);
			if (nMinor <= 1) return true;
			// only bishops on same square color: KBBK
			const diff = abs(countBits(color[Color.white]) - countBits(color[Color.black]));
			if (diff == nMinor && piece[Piece.knight] == 0
				&& ((piece[Piece.bishop] & blackSquares) == piece[Piece.bishop] || (piece[Piece.bishop] & whiteSquares) == piece[Piece.bishop])) return true;
		}

		return false;
	}

	/* verify if a move gives check */
	int giveCheck(const Move m) const {
		const Color enemy = opponent(player);
		const ulong K = piece[Piece.king] & color[enemy];
		const Square from = m.from, to = m.to, k = xKing[enemy];
		const Piece p = m.promotion ? m.promotion : toPiece(cpiece[from]);
		const ulong O = ~piece[Piece.none] ^ from.toBit | to.toBit;
		int check = 0;

		// direct check...
		if (p == Piece.king) {
			if (to == from + 2 && attack(Piece.rook, cast (Square) (from + 1), K, O, player)) ++check;
			else if (to == from - 2 && attack(Piece.rook, cast (Square) (from - 1), K, O, player)) ++check;
		} else if (attack(p, to, K, O, player)) ++check;

		// discovered check
		const ulong P = color[player] & ~(from.toBit | to.toBit);
		const int dirFrom = mask[from].direction[k], dirTo = mask[to].direction[k];
		if (p == Piece.pawn && to == stack[ply].enpassant) {
			const Square ep = to.enpassant;
			if (mask[ep].direction[k]) {
				const ulong Oep = O ^ ep.toBit;
				if (attack(Piece.bishop, k, P & (piece[Piece.bishop] | piece[Piece.queen]), Oep)) ++check;
				else if (attack(Piece.rook, k, P & (piece[Piece.rook] | piece[Piece.queen]), Oep)) ++check;
			}
		} else if (dirFrom != dirTo) {
			if ((dirFrom == 7 || dirFrom == 9) && attack(Piece.bishop, k, P & (piece[Piece.bishop] | piece[Piece.queen]), O)) ++check;
			else if ((dirFrom == 1 || dirFrom == 8) && attack(Piece.rook, k, P & (piece[Piece.rook] | piece[Piece.queen]), O)) ++check;
		}

		return check;
	}

	/* move is an enpassant capture */
	bool isEnpassant(const Move m) const {
		return (stack[ply].enpassant == m.to && toPiece(cpiece[m.from]) == Piece.pawn);
	}


	/* is a move a Capture or a promotion (enpassant capture are omitted) */
	bool isTactical(const Move m) const {
		return (cpiece[m.to] != CPiece.none || (toPiece(cpiece[m.from]) == Piece.pawn && (rank(forward(m.to, player)) >= 6 || stack[ply].enpassant == m.to)));
	}

	/* Count the number of a piece */
	int count(const Piece p, const Color c) const {
		return countBits(piece[p] & color[c]);
	}

	/* Count the number of a colored piece */
	int count(const CPiece p) const {
		return count(toPiece(p), toColor(p));
	}

	/* Play a move on the board */
	void update(const Move move, TranspositionTable *tt = null) {
		const to = move.to.toBit;
		const enemy = opponent(player);
		const p = toPiece(cpiece[move.from]);
		const Stack *u = &stack[ply];
		Stack *n = &stack[ply + 1];

		n.key.update(this, move);
		if (tt) tt.prefetch(n.key);
		n.pawnKey.update(this, move);
		n.castling = u.castling;
		n.enpassant = Square.none;
		n.fifty = cast (byte) (u.fifty + 1);

		if (move != 0) {
			n.victim = toPiece(cpiece[move.to]);
			deplace(move.from, move.to, p);
			if (n.victim) {
				n.fifty = 0;
				capture(n.victim, move.to, enemy);
			}
			if (p == Piece.pawn) {
				n.fifty = 0;
				if (move.promotion) {
					piece[Piece.pawn] ^= to;
					piece[move.promotion] ^= to;
					cpiece[move.to] = toCPiece(move.promotion, player);
				} else if (u.enpassant == move.to) {
					const x = cast (Square) (move.to ^ 8);
					capture(Piece.pawn, x, enemy);
					cpiece[x] = CPiece.none;
				} else if (abs(move.to - move.from) == 16 && (mask[move.to].enpassant & (color[enemy] & piece[Piece.pawn]))) {
					n.enpassant = move.to.enpassant;
				}
			} else if (p == Piece.king) {
				if (move.to == move.from + 2) deplace(move.from.shift(3), move.from.shift(1), Piece.rook);
				else if (move.to == move.from - 2) deplace(move.from.shift(-4), move.from.shift(-1), Piece.rook);
				xKing[player] = move.to;
			}
			n.castling &= (mask[move.from].castling & mask[move.to].castling);
		}

		player = enemy;
		setPinsCheckers(n.checkers, n.pins);
		++ply;
	}

	/* Undo a move on the board */
	void restore(const Move move) {
		const ulong to = move.to.toBit;
		const Color enemy = player;
		const p = move.promotion ? Piece.pawn : toPiece(cpiece[move.to]);
		const Stack *n = &stack[ply];
		const Stack *u = &stack[--ply];

		player = opponent(enemy);
		if (move != 0) {
			deplace(move.to, move.from, p);
			if (n.victim) {
				capture(n.victim, move.to, enemy);
				cpiece[move.to] = toCPiece(n.victim, enemy);
			}
			if (p == Piece.pawn) {
				if (move.promotion) {
					piece[Piece.pawn] ^= to;
					piece[move.promotion] ^= to;
					cpiece[move.from] = toCPiece(Piece.pawn, player);
				} else if (u.enpassant == move.to) {
					const Square x = move.to.enpassant;
					capture(Piece.pawn, x, enemy);
					cpiece[x] = toCPiece(Piece.pawn, enemy);
				}
			} else if (p == Piece.king) {
				if (move.to == move.from + 2) deplace(move.from.shift(1), move.from.shift(3), Piece.rook);
				else if (move.to == move.from - 2) deplace(move.from.shift(-1), move.from.shift(-4), Piece.rook);
				xKing[player] = move.from;
			}
		}
	}

	/* play a sequence of moves */
	void update(const Move [] moves) {
		foreach (m; moves) update(m);
	}

	/* play a sequence of moves */
	void update(const shared Move [] moves) {
		foreach (m; moves) update(m);
	}

	/* restore a sequence of moves */
	void restore(const Move [] moves) {
		foreach_reverse (m; moves) restore(m);
	}

	/* generate evasions */
	void generateEvasions (ref Moves moves) const {
		const Color enemy = opponent(player);
		const ulong occupancy = ~piece[Piece.none];
		const ulong bq = piece[Piece.bishop] | piece[Piece.queen];
		const ulong rq = piece[Piece.rook] | piece[Piece.queen];
		const ulong pinfree = color[player] & ~stack[ply].pins;
		const ulong checkers = stack[ply].checkers;
		const Square k = xKing[player];
		const int[2] push = [8, -8];
		const int pawnPush = push[player];
		ulong attacker, target, o;
		Square from, to, x;

		// king evades
		o = occupancy ^ k.toBit;
		target = attack(Piece.king, k, ~color[player]);
		while (target) {
			to = popSquare(target);
			if (!isSquareAttacked(to, enemy, color[enemy], o)) moves.push(k, to);
		}

		// capture or bloc the (single) checker;
		if (hasSingleBit(checkers)) {
			x = firstSquare(checkers);
			target = mask[k].between[x];

			//enpassant
			to = stack[ply].enpassant;
			if (x == to.enpassant && to != Square.none) {
				from = x.shift(-1);
				if (file(to) > 0 && cpiece[from] == toCPiece(Piece.pawn, player)) {
					o = occupancy ^ from.toBit ^ x.toBit ^ to.toBit;
					if (!attack(Piece.rook, k, rq & color[enemy], o)) moves.push(from, to);
				}
				from = x.shift(+1);
				if (file(to) < 7 && cpiece[from] == toCPiece(Piece.pawn, player)) {
					o = occupancy ^ from.toBit ^ x.toBit ^ to.toBit;
					if (!attack(Piece.rook, k, rq & color[enemy], o)) moves.push(from, to);
				}
			}

			// pawn
			attacker = piece[Piece.pawn] & pinfree;
			if (player == Color.white) generateWhitePawnMoves!(Generate.all)(moves, attacker, checkers, target);
			else generateBlackPawnMoves!(Generate.all)(moves, attacker, checkers, target);

			target |= checkers;

			// knight
			attacker = piece[Piece.knight] & pinfree;
			while (attacker) {
				from = popSquare(attacker);
				generateMoves(moves, attack(Piece.knight, from, target), from);
			}

			// bishop or queen
			attacker = bq & pinfree;
			while (attacker) {
				from = popSquare(attacker);
				generateMoves(moves, attack(Piece.bishop, from, target, occupancy), from);
			}

			// rook or queen
			attacker = rq & pinfree;
			while (attacker) {
				from = popSquare(attacker);
				generateMoves(moves, attack(Piece.rook, from, target, occupancy), from);
			}
		}
	}

	/* generate moves */
	void generateMoves (Generate type = Generate.all) (ref Moves moves) const {
		const Color enemy = opponent(player);
		const ulong occupancy = ~piece[Piece.none];
		const ulong target = type == Generate.all ? ~color[player] : type == Generate.capture ? color[enemy] : piece[Piece.none];
		const ulong pinfree = color[player] & ~stack[ply].pins;
		const ulong bq = piece[Piece.bishop] | piece[Piece.queen];
		const ulong rq = piece[Piece.rook] | piece[Piece.queen];
		const Square k = xKing[player];
		const int[2] push = [8, -8];
		const int pawnPush = push[player];
		ulong attacker, o, attacked;
		Square from, to, x;
		int d;

		// castling
		static if (type != Generate.capture) {
			if (canCastle(kingside[player], k, k + 3, occupancy)) moves.push(k, cast (Square) (k + 2));
			if (canCastle(queenside[player], k, k - 4, occupancy)) moves.push(k, cast (Square) (k - 2));
		}

		// pawn (enpassant)
		static if (type != Generate.quiet) {
			to = stack[ply].enpassant;
			if (to != Square.none) {
				x = to.enpassant;
				from = x.shift(-1);
				if (file(to) > 0 && cpiece[from] == toCPiece(Piece.pawn, player)) {
					o = occupancy ^ (from.toBit | x.toBit | to.toBit);
					if (!attack(Piece.bishop, k, bq & color[enemy], o) && !attack(Piece.rook, k, rq & color[enemy], o)) moves.push(from, to);
				}
				from = x.shift(+1);
				if (file(to) < 7 && cpiece[from] == toCPiece(Piece.pawn, player)) {
					o = occupancy ^ (from.toBit | x.toBit | to.toBit);
					if (!attack(Piece.bishop, k, bq & color[enemy], o) && !attack(Piece.rook, k, rq & color[enemy], o)) moves.push(from, to);
				}
			}
		}

		// pawn (pins)
		attacker = piece[Piece.pawn] & stack[ply].pins;
		while (attacker) {
			const int pawnLeft = pawnPush - 1;
			const int pawnRight = pawnPush + 1;
			from = popSquare(attacker);
			d = mask[k].direction[from];
			static if (type != Generate.quiet) {
				if (d == abs(pawnLeft)) {
					to = cast (Square) (from + pawnLeft);
					if (toColor(cpiece[to]) == enemy) {
						if (rank(forward(from, player)) == 6) moves.pushPromotions(from, to);
						else moves.push(from, to);
					 }
				} else if (d == abs(pawnRight)) {
					to = cast (Square) (from + pawnRight);
					if (toColor(cpiece[to]) == enemy) {
						if (rank(forward(from, player)) == 6) moves.pushPromotions(from, to);
						else moves.push(from, to);
					}
				}
			}
			static if (type != Generate.capture) if (d == abs(pawnPush)) {
				to = cast (Square) (from + pawnPush);
			 	if (cpiece[to] == CPiece.none) {
					moves.push(from, to);
					to = cast (Square) (to + pawnPush);
					if (rank(forward(from, player)) == 1 && cpiece[to] == CPiece.none) moves.push(from, to);
				}
			}
		}

		// pawn (no pins)
		attacker = piece[Piece.pawn] & pinfree;
		if (player == Color.white) generateWhitePawnMoves!type(moves, attacker, color[enemy], piece[Piece.none]);
		else generateBlackPawnMoves!type(moves, attacker, color[enemy], piece[Piece.none]);

		// knight (no pins)
		attacker = piece[Piece.knight] & pinfree;
		while (attacker) {
			from = popSquare(attacker);
			generateMoves(moves, attack(Piece.knight, from, target), from);
		}

		// bishop or queen (pins)
		attacker = bq & stack[ply].pins;
		while (attacker) {
			from = popSquare(attacker);
			d = mask[k].direction[from];
			if (d == 9) generateMoves(moves, diagonalAttack(occupancy, from) & target, from);
			else if (d == 7) generateMoves(moves, antidiagonalAttack(occupancy, from) & target, from);
		}

		// bishop or queen (no pins)
		attacker = bq & pinfree;
		while (attacker) {
			from = popSquare(attacker);
			generateMoves(moves, attack(Piece.bishop, from, target, occupancy), from);
		}

		// rook or queen (pins)
		attacker = rq & stack[ply].pins;
		while (attacker) {
			from = popSquare(attacker);
			d = mask[k].direction[from];
			if (d == 1) generateMoves(moves, rankAttack(occupancy, from) & target, from);
			else if (d == 8) generateMoves(moves, fileAttack(occupancy, from) & target, from);
		}

		// rook or queen (no pins)
		attacker = rq & pinfree;
		while (attacker) {
			from = popSquare(attacker);
			generateMoves(moves, attack(Piece.rook, from, target, occupancy), from);
		}

		// king
		attacked = attack(Piece.king, k, target);
		while (attacked) {
			to = popSquare(attacked);
			if (!isSquareAttacked(to, enemy)) moves.push(k, to);
		}
	}


	/* does a move put its own king in check */
	bool checkOwnKing(const Move move) const {
		const Piece p = toPiece(cpiece[move.from]);
		const Color enemy = opponent(player);
		const CPiece victim = cpiece[move.to];
		ulong E = color[enemy], O = ~piece[Piece.none];

		// king in check after the move ?
		O ^= move.to.toBit | move.from.toBit;
		if (victim) {
			E ^= move.to.toBit;
			O ^= move.to.toBit;
		} else if (p == Piece.pawn && move.to == stack[ply].enpassant) {
			const x = toSquare(file(move.to), rank(move.from));
			E ^= x.toBit;
			O ^= x.toBit;
		}
		Square k = (p == Piece.king ? move.to : xKing[player]);

		return isSquareAttacked(k, enemy, E, O);
	}

	/* is a move legal */
	bool isLegal(const Move move) const {
		const ulong occupancy = ~piece[Piece.none];
		Piece p = toPiece(cpiece[move.from]);
		Color enemy = opponent(player);
		CPiece victim = cpiece[move.to];

		// legal deplacement ?
		if (!legal[p][(move ^ (player * 3640)) & Limits.move.mask])
			return false;

		// move put own king in check
		if (checkOwnKing(move))
			return false;

		// obstacle on a slider's trajectory ?
		if (mask[move.from].between[move.to] & occupancy)
			return false;

		// bad piece color ?
		if (toColor(cpiece[move.from]) != player)
			return false;

		// bad victim ?
		if (victim && (toColor(victim) == player || toPiece(victim) == Piece.king))
			return false;

		// bad pawn move ?
		if (p == Piece.pawn) {
			if (mask[move.from].direction[move.to] == 8 || mask[move.from].direction[move.to] == 16) {
				// push to an empty square ?
				if (victim)
					return false;
			} else {
				if (!victim && move.to != stack[ply].enpassant)
					return false; // capture ?
			}
			if ((rank(move.to) == 0 || rank(move.to) == 7) && !move.promotion)
				return false; // promotion ?
			if (rank(move.to) > 0 && rank(move.to) < 7 && move.promotion)
				return false;
		} else {
			if (move.promotion)
				return false;
		}

		// illegal castling ?
		if (p == Piece.king) {
			Square k = move.from;
			if ((k == move.to - 2) && !canCastle(kingside[player], k, k + 3, occupancy))
				return false;
			if ((k == move.to + 2) && !canCastle(queenside[player], k, k - 4, occupancy))
				return false;
		}

		return true;
	}

	/* get next Attacker to compute SEE */
	Piece nextAttacker(ref ulong [Color.size] board, const Square to, const Color c, ref Piece [Color.size] last, ref int score) const {
		const Color enemy = opponent(c);
		const ulong P = board[c];
		const ulong occupancy = board[c] | board[enemy];
		ulong attacker;
		const Piece [Piece.size] next = [Piece.none, Piece.pawn, Piece.knight, Piece.bishop, Piece.rook, Piece.bishop, Piece.size];

		// remove the last attacker and return the attacker
		Piece victim(Piece p) {
			board[c] ^= (attacker & -attacker);
			last[c] = p;
			if (p == Piece.pawn && rank(forward(to, c)) == 7) {
				p = Piece.queen;
				if (c == player) score += seeValue[p] - seeValue[Piece.pawn];
				else score -= seeValue[p] - seeValue[Piece.pawn];
			}
			return p;
		}

		// loop...
		final switch (next[last[c]]) {
		case Piece.pawn:
			attacker = attack(Piece.pawn, to, piece[Piece.pawn] & P, occupancy, enemy);
			if (attacker) return victim(Piece.pawn);
			goto case;
		case Piece.knight:
			attacker = attack(Piece.knight, to, piece[Piece.knight] & P);
			if (attacker) return victim(Piece.knight);
			goto case;
		case Piece.bishop:
			attacker = attack(Piece.bishop, to, piece[Piece.bishop] & P, occupancy);
			if (attacker) return victim(Piece.bishop);
			goto case;
		case Piece.rook:
			attacker = attack(Piece.rook, to, piece[Piece.rook] & P, occupancy);
			if (attacker) return victim(Piece.rook);
			goto case;
		case Piece.queen:
			attacker = attack(Piece.queen, to, piece[Piece.queen] & P, occupancy);
			if (attacker) return victim(Piece.queen);
			goto case;
		case Piece.king:
			attacker = attack(Piece.king, to, piece[Piece.king] & P);
			if (attacker) return victim(Piece.king);
			goto case;
		case Piece.none, Piece.size:
			return Piece.none;
		}
	}

	/* SEE of a move (before playing it) */
	int see(const Move move) const {
		const Square to = move.to;
		const Color enemy = opponent(player);
		Piece p = toPiece(cpiece[move.from]);
		ulong [Color.size] board = color;
		Piece [Color.size] last = [Piece.pawn, Piece.pawn];
		Piece victim = toPiece(cpiece[to]);
		int score, α, β;

		score = seeValue[victim];
		if (p == Piece.pawn) {
			if (stack[ply].enpassant == to) score = seeValue[victim = Piece.pawn];
			if (move.promotion) score += seeValue[p = move.promotion] - seeValue[Piece.pawn];
		}
		α = score - seeValue[p];
		β = score;

		if (α <= 0) {
			board[player] ^= move.from.toBit;
			score -= seeValue[victim = p];
			if ((p = nextAttacker(board, to, enemy, last, score)) == Piece.none) return β;
			while (true) {
				score += seeValue[victim = p];
				if ((p = nextAttacker(board, to, player, last, score)) == Piece.none || score <= α) return α;
				if (score < β) β = score;

				score -= seeValue[victim = p];
				if ((p = nextAttacker(board, to, enemy, last, score)) == Piece.none || score >= β ) return β;
				if (score > α) α = score;
			}
		}

		return score;
	}

	/* run perft: test correctness & speed of the move generator */
	ulong perft (const int depth, const bool bulk = false, const bool div = false) {
		Moves moves = void;
		ulong count, total;

		moves.generate(this);
		foreach (Move m; moves) {
			update(m);
				if (depth == 1) count = 1;
				else if (depth == 2 && bulk) {
					Moves c = void;
					c.generate(this);
					count = c.length;
				} else count = perft(depth - 1, bulk);
				total += count;
			restore(m);
			if (div) writefln("%5s %16d", m.toPan(), count);
		}

		return total;
	}
}


/* perft with arguments */
void perft(string[] arg, Board init) {
	Board board = init ? init : new Board;
	int depth = 6;
	bool div, help, bulk, loop;
	ulong total;
	Chrono t;
	string fen;

	getopt(arg, "fen|f", &fen, "div", &div, "depth|d", &depth, "loop|l", &loop, "bulk|b", &bulk, "help|h", &help);
	if (help) writeln("perft [--depth|-d <depth>] [--fen|-f <fen>] [--div]  | [--loop|-l] [--bulk|-b] [--help|-h]");
	if (fen.length > 0) board.set(fen);

	writeln(board);
	for (int d = loop ? 0 : depth; d <= depth; ++d) {
		t.start();
		total = d > 0 ? board.perft(d, bulk, div) : 1;
		writefln("perft %d: %d leaves const %.3fs (%.0f leaves/s)", d, total, t.time(), total / t.time());
	}
}

