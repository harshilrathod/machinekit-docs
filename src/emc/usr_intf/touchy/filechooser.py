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


import dircache
import os

class filechooser:
    def __init__(self, gtk, emc, labels, eventboxes, listing):
        self.labels = labels
        self.eventboxes = eventboxes
        self.numlabels = len(labels)
        self.listing = listing
        self.gtk = gtk
        self.emc = emc
        self.emccommand = emc.command()
        self.fileoffset = 0
        self.dir = os.path.join(os.getenv('HOME'), 'emc2', 'nc_files')
        self.files = dircache.listdir(self.dir)
        self.selected = -1
        self.populate()

    def populate(self):
        files = self.files[self.fileoffset:]
        for i in range(self.numlabels):
            l = self.labels[i]
            e = self.eventboxes[i]
            if i < len(files):
                l.set_text(files[i])
            else:
                l.set_text('')
            if self.selected == self.fileoffset + i:
                e.modify_bg(self.gtk.STATE_NORMAL, self.gtk.gdk.color_parse('#fff'))
            else:
                e.modify_bg(self.gtk.STATE_NORMAL, self.gtk.gdk.color_parse('#ccc'))

    def select(self, eventbox, event):
        n = int(eventbox.get_name()[20:])
        self.selected = self.fileoffset + n
        self.emccommand.mode(self.emc.MODE_MDI)
        fn = os.path.join(self.dir, self.labels[n].get_text())
        self.emccommand.program_open(fn)
        self.listing.readfile(fn)
        self.populate()

    def up(self, b):
        self.fileoffset -= self.numlabels
        if self.fileoffset < 0:
            self.fileoffset = 0
        self.populate()

    def down(self, b):
        self.fileoffset += self.numlabels
        self.populate()

    def reload(self, b):
        self.files = dircache.listdir(self.dir)
        self.selected = -1
        self.populate()
