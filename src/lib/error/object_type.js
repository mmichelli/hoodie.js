var HoodieError = require('./error');

/**
 * only lowercase letters, numbers and dashes are allowed for object types,
 * plus must start with a letter.
 *
 * @param {Object} properties
 */
var HoodieObjectTypeError = module.exports = function (properties) {
  properties.name = 'HoodieObjectTypeError';
  properties.message = '"{{type}}" is invalid object type. {{rules}}.';

  this.validTypePattern = /^[a-z$][a-z0-9-]+$/;

  return new HoodieError(properties);
};

HoodieObjectTypeError.isInvalid = function(type, customPattern) {
  return !(customPattern || this.validTypePattern).test(type || '');
};

HoodieObjectTypeError.isValid = function(type, customPattern) {
  return (customPattern || this.validTypePattern).test(type || '');
};

HoodieObjectTypeError.prototype.rules = 'lowercase letters, numbers and dashes allowed only. Must start with a letter';

