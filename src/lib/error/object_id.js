var HoodieError = require('./error');

/**
 *
 * only lowercase letters, numbers and dashes are allowed for object IDs.
 *
 * @param {Object} properties
 */
var HoodieObjectIdError = module.exports = function (properties) {
  properties.name = 'HoodieObjectIdError';
  properties.message = '"{{id}}" is invalid object id. {{rules}}.';

  this.validIdPattern = /^[a-z0-9\-]+$/;

  return new HoodieError(properties);
};


HoodieObjectIdError.isInvalid = function(id, customPattern) {
  return !(customPattern || this.validIdPattern).test(id || '');
};

HoodieObjectIdError.isValid = function(id, customPattern) {
  return (customPattern || this.validIdPattern).test(id || '');
};

HoodieObjectIdError.prototype.rules = 'Lowercase letters, numbers and dashes allowed only. Must start with a letter';

