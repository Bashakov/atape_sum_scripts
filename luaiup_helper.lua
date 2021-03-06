if not ATAPE then
	require "iuplua"
end

OOP = require 'OOP'


ProgressDlg = OOP.class
{
	ctor = function(self, title)
		iup.SetGlobal('UTF8MODE', 1)
		self.cancelflag = false

		local _close_cb = function()
			self.cancelflag = true
			return iup.DEFAULT
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
			title = title or "Report generator",
			--menubox = "NO",
			size = "320x80",
			close_cb = _close_cb,
			resize = "NO",
			layout,
		}

		self.dlgProgress:showxy(iup.CENTER, iup.CENTER)
	end,

	setTitle = function (self, title)
		self.dlgProgress.TITLE = tostring(title)
	end,

	step = function(self, value, text)
		text = text or string.format('progress: %.1f %%', value * 100.0)
		self.label.title = text
		self.gaugeProgress.value = value
		iup.LoopStep()
		if self.cancelflag then
			print('cancaled...')
		end
		return not self.cancelflag
	end,

	Destroy = function(self)
		if (iup and self and self.dlgProgress) then
			iup.Destroy(self.dlgProgress)
		end
	end,

	Hide = function(self)
		iup.Hide(self.dlgProgress)
	end,

	Show = function(self)
		iup.Show(self.dlgProgress)
	end,
}

if HIDE_PROGRESS_DLG then
	ProgressDlg = OOP.class
	{
		ctor = function()
		end,

		setTitle = function ()
		end,

		step = function(_, value, text)
			print(string.format("progress: %.5f: %s", value, text))
			return true
		end,

		Destroy = function()
		end,

		Hide = function()
		end,

		Show = function()
		end,
	}
end

function ShowRadioBtn(title, values, def)
	iup.SetGlobal('UTF8MODE', 1)

	local togles = {}
	local rr = {}
	for i, v in ipairs(values) do
		togles[i] = iup.toggle{title=v}
		rr[v] = i
	end

	local radio = iup.radio{ iup.vbox(togles), value=togles[def],}
	local frame = iup.frame{ radio,	title=title, }

	local cancelbutton = iup.button {
		title = "Ok",
		size = "100x20",
		action = function()
			return iup.CLOSE
		end,
	}
	local abort = false
	local dialog = iup.dialog{
		iup.vbox{
			--frame,
			radio,
			cancelbutton,
			alignment = "ACENTER",
		},
		title=title,
		--size=140,
		resize="NO",
--		menubox = "NO",
		maxbox = "NO",
		minbox = "NO",
		gap="3",
		margin="9x3",
		close_cb = function()
			abort = true
			return iup.CLOSE
		end
	}
	dialog:popup()
	return not abort and rr[radio.value.title]
end

return {
	ProgressDlg = ProgressDlg,
	ShowRadioBtn = ShowRadioBtn
}
