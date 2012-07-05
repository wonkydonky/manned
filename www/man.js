/* The following functions are part of a minimal JS library I wrote for VNDB.org */

var expanded_icon = '▾';
var collapsed_icon = '▸';

function byId(n) {
  return document.getElementById(n)
}
function byName(){
  var d = arguments.length > 1 ? arguments[0] : document;
  var n = arguments.length > 1 ? arguments[1] : arguments[0];
  return d.getElementsByTagName(n);
}
function byClass() { // [class], [parent, class], [tagname, class], [parent, tagname, class]
  var par = typeof arguments[0] == 'object' ? arguments[0] : document;
  var t = arguments.length == 2 && typeof arguments[0] == 'string' ? arguments[0] : arguments.length == 3 ? arguments[1] : '*';
  var c = arguments[arguments.length-1];
  var l = byName(par, t);
  var ret = [];
  for(var i=0; i<l.length; i++)
    if(hasClass(l[i], c))
      ret[ret.length] = l[i];
  return ret;
}

/* wrapper around DOM element creation
 * tag('string') -> createTextNode
 * tag('tagname', tag(), 'string', ..) -> createElement(), appendChild(), ..
 * tag('tagname', { class: 'meh', title: 'Title' }) -> createElement(), setAttribute()..
 * tag('tagname', { <attributes> }, <elements>) -> create, setattr, append */
function tag() {
  if(arguments.length == 1)
    return typeof arguments[0] != 'object' ? document.createTextNode(arguments[0]) : arguments[0];
  var el = typeof document.createElementNS != 'undefined'
    ? document.createElementNS('http://www.w3.org/1999/xhtml', arguments[0])
    : document.createElement(arguments[0]);
  for(var i=1; i<arguments.length; i++) {
    if(arguments[i] == null)
      continue;
    if(typeof arguments[i] == 'object' && !arguments[i].appendChild) {
      for(attr in arguments[i]) {
        if(attr == 'style')
          el.setAttribute(attr, arguments[i][attr]);
        else
          el[ attr == 'class' ? 'className' : attr == 'for' ? 'htmlFor' : attr ] = arguments[i][attr];
      }
    } else
      el.appendChild(tag(arguments[i]));
  }
  return el;
}
function setText(obj, txt) {
  if(obj.textContent != null)
    obj.textContent = txt;
  else
    obj.innerText = txt;
}

function listClass(obj) {
  var n = obj.className;
  if(!n)
    return [];
  return n.split(/ /);
}
function hasClass(obj, c) {
  var l = listClass(obj);
  for(var i=0; i<l.length; i++)
    if(l[i] == c)
      return true;
  return false;
}
function setClass(obj, c, set) {
  var l = listClass(obj);
  var n = [];
  if(set) {
    n = l;
    if(!hasClass(obj, c))
      n[n.length] = c;
  } else {
    for(var i=0; i<l.length; i++)
      if(l[i] != c)
        n[n.length] = l[i];
  }
  obj.className = n.join(' ');
}



/* What follows is specific to manned.org */

// TODO: Fix the 'pkg' link
// TODO: Keep same view when switching to different version of the same man page
// TODO: Allow showing/hiding old package versions individually.
// TODO: Allow complete hiding of old systems. (And enable that by default)

navShowLocales  = false;
navHasLocale    = false;
navHasOldSys    = false;
navHasHiddenSys = false; // OldSys, actually

function navCreate(nav) {
  setText(nav, '');

  navHasLocale = navHasHiddenSys = navHasOldSys = false;
  var dl = tag('dl', null);

  for(var i=0; i<VARS.mans.length; i++) {
    var sys = VARS.mans[i];

    var isold = i > 0 && VARS.mans[i-1][0] == sys[0];
    if(typeof sys[4] === 'undefined')
      sys[4] = !isold;
    navHasOldSys = navHasOldSys || isold;
    navHasHiddenSys = navHasHiddenSys || (isold && !sys[4]);

    var pkgnum = 0;
    var dd = tag('dd', null);

    if(sys[4]) {
      for(var j=0; j<sys[3].length; j++) {
        if(j > 0 && sys[3][j-1][0] == sys[3][j][0])
          continue;

        if(navCreatePkg(dd, sys, sys[3][j]))
          pkgnum++;
      }
    }

    dl.appendChild(tag('dt', sys[1], tag('a',
      {href:'#', _sys: sys, onclick: function() { this._sys[4] = !this._sys[4]; navCreate(nav); return false }},
      sys[4] ? expanded_icon : collapsed_icon)));
    if(sys[4] && pkgnum > 0)
      dl.appendChild(dd);
  }

  navCreateLinks(nav);
  nav.appendChild(dl);
}


function navCreatePkg(dd, sys, pkg) {
  var mannum = 0;
  var pdd = tag('dd', null);

  for(var k=0; k<pkg[2].length; k++) {
    var man = pkg[2][k];
    var txt = man[0] + (man[1] ? '.'+man[1] : '');
    if(man[2] != VARS.hash && man[1])
      navHasLocale = true;
    if(man[2] == VARS.hash || (navShowLocales || !man[1])) {
      if(k > 0)
        pdd.appendChild(tag(' '));
      pdd.appendChild(man[2] == VARS.hash ? tag('b', txt) : tag('a', {href:'/'+VARS.name+'/'+man[2]}, txt));
      mannum++;
    }
  }

  if(mannum > 0) {
    dd.appendChild(tag('dt', tag('a', {href:'/browse/'+sys[2]+'/'+pkg[0]}, pkg[0]), tag('i', pkg[1])));
    dd.appendChild(pdd);
    return true;
  }
  return false;
}


function navCreateLinks(nav) {
  nav.appendChild(tag('a', {'class':'global',href:'#',onclick: function() { }}, collapsed_icon + 'pkg'));

  var t = (navHasHiddenSys ? collapsed_icon : expanded_icon) + 'sys';
  nav.appendChild(!navHasOldSys ? tag('i', {'class':'global'}, t) : tag('a',
    { 'class':'global',
      title:  'Expand/collapse "old" systems.',
      href:   '#',
      onclick: function() {
        for(var i=0; i<VARS.mans.length; i++)
          if(i && VARS.mans[i][0] == VARS.mans[i-1][0])
            VARS.mans[i][4] = navHasHiddenSys;
        navCreate(nav);
        return false
      }
    }, t
  ));

  var t = (navShowLocales ? expanded_icon : collapsed_icon) + 'locales';
  nav.appendChild(!navHasLocale ? tag('i', {'class':'global'}, t) : tag('a',
    { 'class': 'global',
      href:    '#',
      title:   'Show/hide manuals in a non-standard locale.',
      onclick: function() { navShowLocales = !navShowLocales; navCreate(nav); return false }
    }, t
  ));
}


if(byId('nav'))
  navCreate(byId('nav'));



// The "more..." links on the homepage.
if(byId('systems')) {
  var f = function() {
    var l = byName(this.parentNode, 'a', 'hidden');
    for(var i=0; i<l.length; i++)
      setClass(l[i], 'hidden', false);
    setClass(this, 'hidden', true);
    return false
  };
  var l = byClass(byId('systems'), 'a', 'more');
  for(var i=0; i<l.length; i++)
    l[i].onclick = f;
}
