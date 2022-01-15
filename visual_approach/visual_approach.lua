-- Visual Approach LUA Script
-- Author: Maxim Cheusov cheusov@gmail.com

dataref("plane_pitch", "sim/flightmodel/position/theta", "readonly")
dataref("plane_roll", "sim/flightmodel/position/phi", "readonly")
dataref("plane_heading", "sim/flightmodel/position/psi", "readonly")

dataref( "view_type", "sim/graphics/view/view_type" )

create_command( "FlyWithLua/VisualApproach/LookAtRnw", "Look at RNW",
                "start_look_at()", "", "end_look_at()" )


NTF_NON_SUPPORTED_PLANE = 1
NTF_NO_RNW_SET = 2

CAMERA_TIMER = -1
CAMERA_HEADING_START = 0
CAMERA_HEADING_END = 0
CAMERA_PITCH_START = 0
CAMERA_PITCH_END = 0
CAMERA_TRANS_FRAMES = 5


NOTIFICATION_MSG = ""
NOTIFICATION_COLOR = ""
NOTIFICATION_TIMER = 0
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

supported_plane = false
if (findDataRef("laminar/B738/fms/dest_runway_start_lat") ~= nil ) then
  supported_plane = true
  dataref("dst_rnw_lat", "laminar/B738/fms/dest_runway_start_lat", "readonly")
  dataref("dst_rnw_lon", "laminar/B738/fms/dest_runway_start_lon", "readonly")
  dataref("dst_rnw_alt", "laminar/B738/fms/dest_runway_alt", "readonly")
  dataref("dst_icao", "laminar/B738/fms/dest_icao", "readonly")
end

lookAtRnw = false
heading_save = -1
pitch_save = -1
zoom_save = -1

function control_camera()
  if lookAtRnw or CAMERA_TIMER >= 0 then
    local pilot_x, pilot_y, pilot_z, _, _ = get_pilots_head() 
    if CAMERA_TIMER >= 0 then
      local d_h = math.max(CAMERA_HEADING_START, CAMERA_HEADING_END) - math.min(CAMERA_HEADING_START, CAMERA_HEADING_END)
      if lookAtRnw then
        CAMERA_HEADING_END, CAMERA_PITCH_END = get_pilot_hdg_pitch()
      end
      if d_h > 180 then
        if CAMERA_HEADING_START < CAMERA_HEADING_END then
          CAMERA_HEADING_START = 360 + CAMERA_HEADING_START
        else
          CAMERA_HEADING_START = CAMERA_HEADING_START - 360
        end
      end

      local time =  1 - CAMERA_TIMER / CAMERA_TRANS_FRAMES
      local new_heading = CAMERA_HEADING_START + (CAMERA_HEADING_END - CAMERA_HEADING_START) * time
      local new_pitch = CAMERA_PITCH_START + (CAMERA_PITCH_END - CAMERA_PITCH_START) * time
      if new_heading < 0 then
        new_heading = 360 + new_heading
      end
      if new_heading > 360 then
        new_heading = new_heading - 360
      end

      set_pilots_head(pilot_x, pilot_y, pilot_z, new_heading, new_pitch)
      CAMERA_TIMER = CAMERA_TIMER - 1 
    else
      local hdg, pitch = get_pilot_hdg_pitch()
      set_pilots_head(pilot_x, pilot_y, pilot_z, hdg, pitch)
    end
  end
  if NOTIFICATION_TIMER > 0 then
    draw_string(5, SCREEN_HIGHT - 10, NOTIFICATION_MSG, NOTIFICATION_COLOR)
    NOTIFICATION_TIMER = NOTIFICATION_TIMER - 1
  end
end

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

function get_pilot_hdg_pitch()
    local camera_pos = ffi.new("XPLMCameraPosition_t")
    local rnw_x, rnw_y, rnw_z = get_rwn_pos()
    XPLM.XPLMReadCameraPosition(camera_pos)
    local pilot_x, pilot_y, pilot_z, pilot_hdg, pilot_pitch = get_pilots_head() 
    local l_x, l_y, l_z = local2plane(rnw_x,  rnw_y,  rnw_z, plane_heading, -plane_pitch, plane_roll, camera_pos.x, camera_pos.y, camera_pos.z)
    local l_hdg, l_pitch, _ = get_hdg_dst(pilot_x, pilot_y, pilot_z, l_x, l_y, l_z)
    return l_hdg, l_pitch
end

function check_support()
  if ( view_type == 1026 ) then
    if (not supported_plane) then
      show_notification(NTF_NON_SUPPORTED_PLANE)
      return false
    elseif dst_rnw_lat == 0 then
      show_notification(NTF_NO_RNW_SET)
      return false
    end
    return true
  end
  return false
end

function set_notification(msg, color)
  NOTIFICATION_MSG = msg
  NOTIFICATION_COLOR = color
  NOTIFICATION_TIMER = 90
end

function show_notification(nid)
  if nid == NTF_NON_SUPPORTED_PLANE then
    set_notification("This plane is not Zibo 737-800", "red")
  end
  if nid == NTF_NO_RNW_SET then
    set_notification("Set destanation aiprort/runway in FMS", "red")
  end
end

function start_look_at()
  if check_support() then
    _, _, _, heading_save, pitch_save = get_pilots_head()
    CAMERA_TIMER = CAMERA_TRANS_FRAMES
    CAMERA_HEADING_START = heading_save
    CAMERA_PITCH_START = pitch_save
    lookAtRnw = true
  end
end

function end_look_at()
  if lookAtRnw then
    CAMERA_TIMER = CAMERA_TRANS_FRAMES
    local _, _, _, hdp, picth = get_pilots_head()
    CAMERA_HEADING_START = hdp
    CAMERA_PITCH_START = picth
    CAMERA_HEADING_END = heading_save
    CAMERA_PITCH_END = pitch_save
    lookAtRnw = false
  end
end

do_every_draw("control_camera()")
