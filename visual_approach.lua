-- Visual Approach LUA Script
-- Author: Maxim Cheusov cheusov@gmail.com


dataref("local_x", "sim/flightmodel/position/local_x", "readonly")
dataref("local_y", "sim/flightmodel/position/local_y", "readonly")
dataref("local_z", "sim/flightmodel/position/local_z", "readonly")

dataref("plane_pitch", "sim/flightmodel/position/theta", "readonly")
dataref("plane_roll", "sim/flightmodel/position/phi", "readonly")
dataref("plane_heading", "sim/flightmodel/position/psi", "readonly")

dataref( "view_type", "sim/graphics/view/view_type" )

create_command( "FlyWithLua/VisualApprach/LookAtRnw", "Look at RNW",
                "start_look_at()", "", "end_look_at()" )


---------------------------------------------------
-- Init. XPLM lib.
---------------------------------------------------
-- https://forums.x-plane.org/index.php?/forums/topic/123390-xplm-library-how-to-load-and-use/
-- first we need ffi module (variable must be declared local)
local ffi = require("ffi")

-- find the right lib to load
local XPLMlib = ""
if SYSTEM == "IBM" then
  -- Windows OS (no path and file extension needed)
  if SYSTEM_ARCHITECTURE == 64 then
    XPLMlib = "XPLM_64"  -- 64bit
  else
    XPLMlib = "XPLM"     -- 32bit
  end
elseif SYSTEM == "LIN" then
  -- Linux OS (we need the path "Resources/plugins/" here for some reason)
  if SYSTEM_ARCHITECTURE == 64 then
    XPLMlib = "Resources/plugins/XPLM_64.so"  -- 64bit
  else
    XPLMlib = "Resources/plugins/XPLM.so"     -- 32bit
  end
elseif SYSTEM == "APL" then
  -- Mac OS (we need the path "Resources/plugins/" here for some reason)
  XPLMlib = "Resources/plugins/XPLM.framework/XPLM" -- 64bit and 32 bit
else
  return -- this should not happen
end

-- load the lib and store in local variable
local XPLM = ffi.load(XPLMlib)

ffi.cdef("void XPLMWorldToLocal(double inLatitude, double inLongitude, double inAltitude, double * outX, double * outY, double * outZ);")
ffi.cdef("typedef void * XPLMDataRef;")
ffi.cdef("XPLMDataRef XPLMFindDataRef(const char * inDataRefName);")
ffi.cdef([[typedef struct {
  float x;
  float y;
  float z;
  float pitch;
  float heading;
  float roll;
  float zoom;
} XPLMCameraPosition_t;

typedef int (* XPLMCameraControl_f)(
  XPLMCameraPosition_t * outCameraPosition,    /* Can be NULL */
  int inIsLosingControl,    
  void *inRefcon);

void XPLMControlCamera(
  int inHowLong,    
  XPLMCameraControl_f inControlFunc,    
  void *inRefcon);
void XPLMDontControlCamera(void);
void XPLMReadCameraPosition(XPLMCameraPosition_t * outCamPos);
]])

function findDataRef(dataRefName)
  if XPLM then
    return XPLM.XPLMFindDataRef(dataRefName)
    end
  return nil
end

if (findDataRef("laminar/B738/fms/dest_runway_start_lat")) then
  dataref("dst_rnw_lat", "laminar/B738/fms/dest_runway_start_lat", "readonly")
  dataref("dst_rnw_lon", "laminar/B738/fms/dest_runway_start_lon", "readonly")
  dataref("dst_rnw_alt", "laminar/B738/fms/des_icao_alt", "readonly")
end

lookAtRnw = false
heading_save = -1
pitch_save = -1
-- pilot_heading_save = -1
-- pilot_pitch = -1
pilot_x_w = -1
pilot_y_w = -1
pilot_z_w = -1

function rotate_x(x, y, z, a)
  ret_y = y * math.cos(a) + z * math.sin(a)
  ret_z = - y * math.sin(a) + z * math.cos(a)
  return x, ret_y, ret_z
end

function rotate_y(x, y, z, a)
  ret_x = x * math.cos(a) - z * math.sin(a)
  ret_z = x * math.sin(a) + z * math.cos(a)
  return ret_x, y, ret_z
end

function rotate_z(x, y, z, a)
  ret_x = x * math.cos(a) - y * math.sin(a)
  ret_y = - x * math.sin(a) + y * math.cos(a)
  return ret_x, ret_y, z
end

function local2plane(x, y, z, hdg, pitch, roll, x_plane, y_plane, z_plane)
  local hdg = math.rad(-hdg)
  local pitch = math.rad(-pitch)
  local roll = math.rad(-roll)
  local x = x - x_plane
  local y = y - y_plane
  local z = z - z_plane

  x, y, z = rotate_y(x, y, z, hdg)
  x, y, z = rotate_x(x, y, z, pitch)
  x, y, z = rotate_z(x, y, z, roll)
  return x, y, z
end

function get_rwn_pos()
  local outX = ffi.new("double[1]")
  local outY = ffi.new("double[1]")
  local outZ = ffi.new("double[1]")
  XPLM.XPLMWorldToLocal(dst_rnw_lat, dst_rnw_lon, dst_rnw_alt * 0.3048, outX, outY, outZ )
  return outX[0], outY[0], outZ[0]
end

function get_hdg_dst(c_x, c_y, c_z, r_x, r_y, r_z)
  local dX = c_x - r_x
  local dY = c_y - r_y
  local dZ = c_z - r_z

  local hdg = math.deg(math.atan2(dX, dZ))
  if hdg < 0 then
    hdg = math.abs(hdg)
  else
    hdg = 360 - hdg
  end
  local dst = math.sqrt(dX*dX + dZ*dZ + dY*dY)
  local pitch = - (90 - math.deg(math.atan2(dst, dY)))
  return hdg, pitch, dst
end

function look_at_rnw()
  if (( view_type == 1026 ) and lookAtRnw) then
    local camera_pos = ffi.new("XPLMCameraPosition_t")
    local rnw_x, rnw_y, rnw_z = get_rwn_pos()
    XPLM.XPLMReadCameraPosition(camera_pos)
    local pilot_x, pilot_y, pilot_z, pilot_hdg, pilot_pitch = get_pilots_head() 
    local l_x, l_y, l_z = local2plane(rnw_x,  rnw_y,  rnw_z, plane_heading, -plane_pitch, plane_roll, camera_pos.x, camera_pos.y, camera_pos.z)
    local l_hdg, l_pitch, l_dst = get_hdg_dst(pilot_x, pilot_y, pilot_z, l_x, l_y, l_z)
    set_pilots_head(pilot_x, pilot_y, pilot_z, l_hdg, l_pitch)
  end
end

function  start_look_at()
  pilot_x, pilot_y, pilot_z, heading_save, pitch_save = get_pilots_head()
  lookAtRnw = true
end

function  end_look_at()
  local pilot_x, pilot_y, pilot_z, heading, pitch = get_pilots_head()
  set_pilots_head(pilot_x, pilot_y, pilot_z, heading_save, pitch_save)
  lookAtRnw = false
end

do_every_draw("look_at_rnw()")
