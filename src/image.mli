open! Core

(**
   The [Image] module provides functions to manipulate 2D images in the Portable Pixmap
   (PPM) format. Each pixel in the image is represented using the [Pixel.t] type. The main
   type provided by this module is [t], which represents the images. The pixel at position
   0,0 is the top left corner of the image.

   Here's an outline of the functionalities provided by this module:

   - Loading and saving PPM images
   - Querying image properties (width, height, max value)
   - Getting and setting individual pixels
   - Mapping, folding and iterating over pixels in an image
   - Copying and slicing images
   - Generating images with a constant pixel color
*)

type t

(** [load_ppm ~filename] reads a PPM image from the given [filename] and returns an image
    of type [t]. Raises [Sys_error] if the file cannot be read, and an exception if the
    PPM format is invalid. *)
val load_ppm : filename:string -> t

(** Convert a [t] to a [Graphics.image] that can be displayed with [Graphics.draw_image]. *)
val to_graphics_image : t -> Graphics.image

(** Convert a [Graphics.image] to a [t]. *)
val of_graphics_image : Graphics.image -> t

(** [width image] returns the width of the given [image]. *)
val width : t -> int

(** [height image] returns the height of the given [image]. *)
val height : t -> int

(** [max_val image] returns the maximum allowed pixel value of the given [image]. *)
val max_val : t -> int

(** [get image ~x ~y] returns the pixel at position [(x, y)] of the given [image]. If the
    coordinates are out of bounds, it raises an exception. *)
val get : t -> x:int -> y:int -> Pixel.t

(** [set image ~x ~y pixel] sets the pixel at position [(x, y)] of the given [image] to
    the given [pixel]. If the coordinates are out of bounds, it raises an exception. *)
val set : t -> x:int -> y:int -> Pixel.t -> unit

(** [map image ~f] applies the given function [f] to each pixel of the [image] and returns
    a new image with the transformed pixels. *)
val map : t -> f:(Pixel.t -> Pixel.t) -> t

(** [mapi image ~f] applies the given function [f] with positions (in [x] and [y]) to each
    pixel of the [image] and returns a new image with the transformed pixels. *)
val mapi : t -> f:(x:int -> y:int -> Pixel.t -> Pixel.t) -> t

(** [fold image ~init ~f] folds the given function [f] over all the pixels of the [image],
    accumulating the result in a value of type ['acc]. *)
val fold : t -> init:'acc -> f:('acc -> Pixel.t -> 'acc) -> 'acc

(** [foldi image ~init ~f] folds the given function [f] with positions (in [x] and [y])
    over all the pixels of the [image], accumulating the result in a value of type
    ['acc]. *)
val foldi : t -> init:'acc -> f:(x:int -> y:int -> 'acc -> Pixel.t -> 'acc) -> 'acc

(** [save_ppm image ~filename] writes the given [image] to the given [filename] in PPM
    format. Raises [Sys_error] if the file cannot be written. *)
val save_ppm : t -> filename:string -> unit

(** [copy image] returns a new image that is a copy of the given [image]. *)
val copy : t -> t

(** [slice image ~x_start ~x_end ~y_start ~y_end] returns a new image that is a sub-region
    of the [image], with [x] coordinates between [x_start] (inclusive) and [x_end]
    (exclusive), and [y] coordinates between [y_start] (inclusive) and [y_end]
    (exclusive). If any of the coordinates are out of bounds or if [x_end <= x_start] or
    [y_end <= y_start], the function raises an exception. *)
val slice : t -> x_start:int -> x_end:int -> y_start:int -> y_end:int -> t

(** [mean_pixel image] calculates the average of all the pixels in the [image] and returns
    the mean pixel value as [Pixel.t]. If the image is empty (width and height of 0), the
    functions raises an exception. *)
val mean_pixel : t -> Pixel.t

(** [make ?max_val ~width ~height pixel] returns a new image of the given [width] and
    [height] filled with the given [pixel] value. Optionally, [max_val] can be provided to
    set the maximum pixel value (default is 255). If [width] or [height] is non-positive,
    the function raises an exception. *)
val make : ?max_val:int -> width:int -> height:int -> Pixel.t -> t
