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

/* Structure of VARS.mans:
  [
    ["System", "Full name", "short", [
        [ "package", "version", [
            [ "section", "locale"||null ],
            ...
          ],
          oldvisible // <- this is only set by JS
        ],
        ...
      ],
      oldvisible // <- this is only set by JS
    ],
    ...
  ]
*/

navShowLocales  = false;
navHasLocale    = false;

function navCreate(nav) {
  setText(nav, '');

  navHasLocale = false;
  var dl = tag('dl', null);

  for(var i=0; i<VARS.mans.length; i++) {
    var sys = VARS.mans[i];

    var isold = i > 0 && VARS.mans[i-1][0] == sys[0];
    if(typeof sys[4] === 'undefined')
      sys[4] = !isold;

    var pkgnum = 0;
    var dd = tag('dd', null);

    if(sys[4])
      for(var j=0; j<sys[3].length; j++)
        if(navCreatePkg(nav, dd, sys, j))
          pkgnum++;

    if(!isold || sys[4])
      dl.appendChild(tag('dt',
        isold || !VARS.mans[i+1] || VARS.mans[i+1][0] != sys[0] ? null : tag('a',
          {href:'#', _sysn: sys[0], _sysi:i, onclick: function() {
            for(var j=this._sysi+1; j<VARS.mans.length && VARS.mans[j][0] == this._sysn; j++)
              VARS.mans[j][4] = !VARS.mans[j][4];
            navCreate(nav);
            return false
          }}, VARS.mans[i+1][4] ? expanded_icon : collapsed_icon),
        sys[1]
      ));

    if(sys[4] && pkgnum > 0)
      dl.appendChild(dd);
  }

  navCreateLinks(nav);
  nav.appendChild(dl);
}


function navCreatePkg(nav, dd, sys, n) {
  var pkg = sys[3][n];

  var isold = n > 0 && sys[3][n-1][0] == pkg[0];
  if(isold && !pkg[3])
    return false;

  var mannum = 0;
  var pdd = tag('dd', null);
  for(var i=0; i<pkg[2].length; i++) {
    var man = pkg[2][i];
    var txt = man[0] + (man[1] ? '.'+man[1] : '');
    if(man[2] != VARS.hash && man[1])
      navHasLocale = true;
    if(man[2] == VARS.hash || (navShowLocales || !man[1])) {
      if(i > 0)
        pdd.appendChild(tag(' '));
      pdd.appendChild(man[2] == VARS.hash ? tag('b', txt) : tag('a', {href:'/'+VARS.name+'/'+man[2]}, txt));
      mannum++;
    }
  }

  if(mannum > 0) {
    dd.appendChild(tag('dt',
      isold || !sys[3][n+1] || sys[3][n+1][0] != pkg[0] ? null : tag('a',
        {href:'#', _pkgn: pkg[0], _pkgi:n, onclick: function() {
          for(var j=this._pkgi+1; j<sys[3].length && sys[3][j][0] == this._pkgn; j++)
            sys[3][j][3] = !sys[3][j][3];
          navCreate(nav);
          return false
        }}, sys[3][n+1][3] ? expanded_icon : collapsed_icon),
      tag('a', {href:'/browse/'+sys[2]+'/'+pkg[0]+'/'+pkg[1]}, pkg[0]), tag('i', pkg[1])));
    dd.appendChild(pdd);
    return true;
  }
  return false;
}


function navCreateLinks(nav) {
  nav.appendChild(tag('a', {'class':'global',href:'#',onclick: function() { alert("Not implemented yet."); return false }}, collapsed_icon + 'pkg'));

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
