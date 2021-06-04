open Base
open Scad_ml
open Sigs

module Kind = struct
  type niz =
    { clip_height : float
    ; snap_slot_h : float
    }

  type _ t =
    | Mx : unit -> unit t
    | Niz : niz -> niz t
end

module type Config = sig
  type k
  type spec = k Kind.t

  val spec : spec
  val outer_w : float
  val inner_w : float
  val thickness : float
  val clip : Model.t -> Model.t
end

module Face = struct
  module Points = struct
    type t =
      { top_left : Core.pos_t
      ; top_right : Core.pos_t
      ; bot_left : Core.pos_t
      ; bot_right : Core.pos_t
      ; centre : Core.pos_t
      }

    let make (x, y, _) =
      { top_left = x /. -2., y /. 2., 0.
      ; top_right = x /. 2., y /. 2., 0.
      ; bot_left = x /. -2., y /. -2., 0.
      ; bot_right = x /. 2., y /. -2., 0.
      ; centre = 0., 0., 0.
      }

    let map ~f t =
      { top_left = f t.top_left
      ; top_right = f t.top_right
      ; bot_left = f t.bot_left
      ; bot_right = f t.bot_right
      ; centre = f t.centre
      }

    let fold ~f ~init t =
      let flipped = Fn.flip f in
      f init t.top_left
      |> flipped t.top_right
      |> flipped t.bot_left
      |> flipped t.bot_right

    let translate p = map ~f:(Math.add p)
    let rotate r = map ~f:(Math.rotate r)
    let rotate_about_pt r p = map ~f:(Math.rotate_about_pt r p)
  end

  type t =
    { scad : Model.t
    ; points : Points.t
    }

  let make size = { scad = Model.cube ~center:true size; points = Points.make size }

  let translate p t =
    { scad = Model.translate p t.scad; points = Points.translate p t.points }

  let rotate r t = { scad = Model.rotate r t.scad; points = Points.rotate r t.points }

  let rotate_about_pt r p t =
    { scad = Model.rotate_about_pt r p t.scad
    ; points = Points.rotate_about_pt r p t.points
    }
end

module Faces = struct
  type t =
    { north : Face.t
    ; south : Face.t
    ; east : Face.t
    ; west : Face.t
    }

  let map ~f t =
    { north = f t.north; south = f t.south; east = f t.east; west = f t.west }

  let fold ~f ~init t =
    let flipped = Fn.flip f in
    f init t.north |> flipped t.south |> flipped t.east |> flipped t.west

  let make width depth =
    let half_w = width /. 2. in
    let rot_lat = Face.rotate (0., 0., Math.pi /. 2.) in
    let base = Face.rotate (Math.pi /. 2., 0., 0.) (Face.make (width, depth, 0.1)) in
    { north = Face.translate (0., half_w, 0.) base
    ; south = Face.translate (0., -.half_w, 0.) base
    ; west = base |> rot_lat |> Face.translate (-.half_w, 0., 0.)
    ; east = base |> rot_lat |> Face.translate (half_w, 0., 0.)
    }

  let translate p = map ~f:(Face.translate p)
  let rotate r = map ~f:(Face.rotate r)
  let rotate_about_pt r p = map ~f:(Face.rotate_about_pt r p)
end

type t =
  { scad : Model.t
  ; origin : Core.pos_t
  ; faces : Faces.t
  }

module type S = sig
  include Config
  include Transformable with type t := t

  type nonrec t = t

  val t : t
end

module Make (C : Config) : S = struct
  include C

  type nonrec t = t

  let translate p t =
    { scad = Model.translate p t.scad
    ; origin = Math.add p t.origin
    ; faces = Faces.translate p t.faces
    }

  let rotate r t =
    { scad = Model.rotate r t.scad
    ; origin = Math.rotate r t.origin
    ; faces = Faces.rotate r t.faces
    }

  let rotate_about_pt r p t =
    { scad = Model.rotate_about_pt r p t.scad
    ; origin = Math.rotate_about_pt r p t.origin
    ; faces = Faces.rotate_about_pt r p t.faces
    }

  let hole =
    let outer = Model.cube ~center:true (outer_w, outer_w, thickness) in
    let inner = Model.cube ~center:true (inner_w, inner_w, thickness +. 0.1) in
    Model.difference outer [ inner ]

  let scad = clip hole
  let t = { scad; origin = 0., 0., 0.; faces = Faces.make outer_w thickness }
end

module RotateClips (K : S) : S = struct
  include K

  let t =
    let t' = rotate (0., 0., Math.pi /. 2.) t in
    let { faces = { north; south; east; west }; _ } = t' in
    { t' with faces = { north = east; south = west; east = south; west = north } }
end

(* NOTE: These key angle finding functions assume that the key in question is a part
 * of a column parallel to the y-axis *)
let x_angle { faces = { west = { points = { top_left; top_right; _ }; _ }; _ }; _ } =
  let _, dy, dz = Util.(top_right <-> top_left) in
  Float.atan (dz /. dy)

(* TODO: untested. To be used with side walls. *)
let y_angle { faces = { south = { points = { top_left; top_right; _ }; _ }; _ }; _ } =
  let dx, _, dz = Util.(top_right <-> top_left) in
  Float.atan (dz /. dx)
