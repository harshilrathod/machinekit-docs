# Touchy is Copyright (c) 2009  Chris Radek <chris@timeguy.com>
#
# Touchy is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 2 of the License, or
# (at your option) any later version.
#
# Touchy is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.



class listing:
    def __init__(self, gtk, emc, labels, eventboxes):
        self.labels = labels
        self.eventboxes = eventboxes
        self.numlabels = len(labels)
        self.gtk = gtk
        self.emc = emc
        self.lineoffset = 0
        self.selected = -1
        self.filename = ""
        self.program = []
        self.populate()

    def populate(self):
        program = self.program[self.lineoffset:self.lineoffset + self.numlabels]
        for i in range(self.numlabels):
            l = self.labels[i]
            e = self.eventboxes[i]
            if i < len(program):
                l.set_text(program[i].rstrip())
            else:
                l.set_text('')
#            if self.selected == self.lineoffset + i:
#                e.modify_bg(self.gtk.STATE_NORMAL, self.gtk.gdk.color_parse('#fff'))
#            else:
#                e.modify_bg(self.gtk.STATE_NORMAL, self.gtk.gdk.color_parse('#ccc'))

    def up(self, b):
        self.lineoffset -= self.numlabels
        if self.lineoffset < 0:
            self.lineoffset = 0
        self.populate()

    def down(self, b):
        self.lineoffset += self.numlabels
        self.populate()

    def readfile(self, fn):
        self.filename = fn
        f = file(fn, 'r')
        self.program = f.readlines()
        f.close()
        self.lineoffset = 0
        self.populate()

    def reload(self, b):
        pass
