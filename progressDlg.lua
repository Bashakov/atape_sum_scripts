if not ATAPE then
	require "iuplua" 
	socket = require 'socket'
end

OOP = require 'OOP'


ProgressDlg = OOP.class
{
	ctor = function(self)
		self.cancelflag = false
		
		local _close_cb = function()
			self.cancelflag = true
			--return iup.CLOSE
		end

		self.cancelbutton = iup.button {
			title = "Cancel",
			size = "100x20",
			action = _close_cb,
		}
	
		self.label = iup.label{title="Progress", size = "300x20"}
		
		self.gaugeProgress = iup.progressbar{ expand="HORIZONTAL", size = "300x20", value = 0.0}
	
		local layout = iup.vbox {
				self.label,
				self.gaugeProgress,
				iup.fill{},
				iup.hbox{
					iup.fill{},
					self.cancelbutton,
					iup.fill{},
				}
			}
	
		self.dlgProgress = iup.dialog{
			title = "Report generator",
			--menubox = "NO",
			size = "320x80",
			close_cb = _close_cb,
			layout,
		}
		
		self.dlgProgress:showxy(iup.CENTER, iup.CENTER)
	end,
	
	step = function(self, value, text)
		text = text or stuff.sprintf('progress: %.1f %%', value * 100.0)
		self.label.title = text
		self.gaugeProgress.value = value
		iup.LoopStep()
		return not self.cancelflag
	end
}

return ProgressDlg
