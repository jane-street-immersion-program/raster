open! Core

(** Pixel Module

    The [Pixel] module provides a representation and utility functions for working with
    RGB-color pixels. Each pixel is represented as a tuple of three integer values, one
    each for the red, green, and blue (RGB) channels.
*)

(** [t] is a tuple of three integers, representing the red, green, and blue channels of an
    RGB color pixel. *)
type t = int * int * int [@@deriving sexp]

(** [red t] returns the value of the red channel of the pixel [t]. *)
val red : t -> int

(** [green t] returns the value of the green channel of the pixel [t]. *)
val green : t -> int

(** [blue t] returns the value of the blue channel of the pixel [t]. *)
val blue : t -> int

(** [zero] is a constant representing a black pixel. It is equivalent to the pixel value
    [(0, 0, 0)]. *)
val zero : t

(** [p1 + p2] returns a new pixel value formed by component-wise addition of [p1] and
    [p2]. *)
val ( + ) : t -> t -> t

(** [of_int x] returns an equivalent pixel value, where each channel has the same integer
    value [x]. This function is most useful when working with grayscale colors. *)
val of_int : int -> t

(** [to_string t] returns a string representation of the pixel [t] in the format "R G B",
    where R, G, and B are the integer values of the red, green, and blue channels,
    respectively. *)
val to_string : t -> string
